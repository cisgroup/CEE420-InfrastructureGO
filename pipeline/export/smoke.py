"""A first run through the whole export chain, before any model of ours exists.

The app's promise is a verdict on the phone, and that hangs on three things nobody had seen work on this Mac. A
PyTorch network has to convert to Core ML, the converted network has to say what the PyTorch network says, and a
photograph has to reach it through Vision much as it reaches the pipeline through Pillow. This script tries all
three with a network that is already trained, torchvision's ResNet-18 with its ImageNet weights, because a trained
network answers confidently and so shows a difference where an untrained one would hide it. Our classifier is the
same network with another last layer, so what holds here holds for it.

    uv run --project pipeline/export python pipeline/export/smoke.py

It reads the private converted photographs when they exist and writes everything under build/smoke, which git
ignores. The last line says whether the chain held.
"""

import argparse
import json
import subprocess
import sys
import warnings
from pathlib import Path

import numpy as np
import torch
import torchvision
from PIL import Image

warnings.filterwarnings("ignore", category=SyntaxWarning)
import coremltools as ct  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "smoke"
PHOTOS = ROOT / "data" / "private" / "converted"
SIZE = 224
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)
CORE_ML_TOLERANCE = 0.02        # the most a probability may move between PyTorch and Core ML on the same pixels
FILTERS = {"nearest": Image.Resampling.NEAREST, "box": Image.Resampling.BOX, "bilinear": Image.Resampling.BILINEAR,
           "hamming": Image.Resampling.HAMMING, "bicubic": Image.Resampling.BICUBIC, "lanczos": Image.Resampling.LANCZOS}


class Wrapped(torch.nn.Module):
    """The network as the phone sees it. Pixels from 0 to 1 go in, the normalisation happens inside, probabilities come out."""

    def __init__(self, network):
        super().__init__()
        self.network = network
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(STD).view(1, 3, 1, 1))

    def forward(self, x):
        return torch.softmax(self.network((x - self.mean) / self.std), dim=1)


def centre_square(image):
    side = min(image.size)
    left, top = (image.width - side) // 2, (image.height - side) // 2
    return image.crop((left, top, left + side, top + side))


def chip(image, resample):
    """The largest centred square of a picture at the network's size."""
    return centre_square(image.convert("RGB")).resize((SIZE, SIZE), resample)


def torch_probabilities(model, chips):
    x = torch.from_numpy(np.stack([np.asarray(c, dtype=np.float32) / 255.0 for c in chips])).permute(0, 3, 1, 2)
    with torch.no_grad():
        return model(x).numpy()


def shrink(source, target, long_side=2048):
    """A photograph the way the app and the dataset keep it, the long side at 2048 pixels and nothing but pixels."""
    with Image.open(source) as image:
        image = image.convert("RGB")
        image.thumbnail((long_side, long_side), Image.Resampling.LANCZOS)
        Image.fromarray(np.asarray(image)).save(target, "JPEG", quality=90)
    return target


def main(argv=None):
    parser = argparse.ArgumentParser(description="A first run through the whole export chain.")
    parser.add_argument("--photos", type=Path, default=PHOTOS, help="a folder of photographs to send through Vision")
    args = parser.parse_args(argv)
    OUT.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(20261012)
    report = {"versions": {"coremltools": ct.__version__, "torch": torch.__version__, "torchvision": torchvision.__version__}}

    network = torchvision.models.resnet18(weights=torchvision.models.ResNet18_Weights.IMAGENET1K_V1).eval()
    model = Wrapped(network).eval()
    labels = [f"c{k:04d}" for k in range(1000)]
    traced = torch.jit.trace(model, torch.rand(1, 3, SIZE, SIZE))
    converted = ct.convert(traced, inputs=[ct.ImageType(name="image", shape=(1, 3, SIZE, SIZE), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
                           classifier_config=ct.ClassifierConfig(labels), convert_to="mlprogram",
                           minimum_deployment_target=ct.target.iOS17, compute_precision=ct.precision.FLOAT16)
    converted.short_description = "A smoke test of the export chain, torchvision's ResNet-18 with its ImageNet weights"
    converted.user_defined_metadata["run"] = "smoke"
    converted.user_defined_metadata["classes"] = "the thousand ImageNet classes, named by number"
    package = OUT / "Smoke.mlpackage"
    converted.save(str(package))
    spec = converted.get_spec()
    report["converted"] = {"package": str(package.relative_to(ROOT)), "megabytes": round(sum(f.stat().st_size for f in package.rglob("*") if f.is_file()) / 1e6, 1),
                           "outputs": [o.name for o in spec.description.output], "metadata_reads_back": ct.models.MLModel(str(package)).user_defined_metadata.get("run") == "smoke"}
    probability_name = spec.description.predictedProbabilitiesName

    # one, the converted network against the PyTorch network on the very same pixels
    rng = np.random.default_rng(20261012)
    chips = [Image.fromarray(rng.integers(0, 256, (SIZE, SIZE, 3), dtype=np.uint8))]
    photos = sorted(p for p in args.photos.glob("*.jpg")) if args.photos.exists() else []
    small = []
    for photo in photos:
        small.append(shrink(photo, OUT / "photos" / photo.name) if (OUT / "photos").mkdir(exist_ok=True) is None else None)
    with_photos = [Image.open(p) for p in small]
    chips += [chip(image, Image.Resampling.BILINEAR) for image in with_photos]
    ours = torch_probabilities(model, chips)
    theirs = np.stack([[converted.predict({"image": c})[probability_name][label] for label in labels] for c in chips])
    gap = np.abs(ours - theirs)
    report["core_ml_against_pytorch"] = {
        "pictures": len(chips), "largest_probability_difference": round(float(gap.max()), 5), "mean_probability_difference": round(float(gap.mean()), 7),
        "top_class_agrees_on": int((ours.argmax(1) == theirs.argmax(1)).sum()), "tolerance": CORE_ML_TOLERANCE,
        "held": bool(gap.max() < CORE_ML_TOLERANCE and (ours.argmax(1) == theirs.argmax(1)).all()),
    }

    # two, the photographs through Vision's centre crop against the same photographs through Pillow
    if small:
        script = ROOT / "tools" / "vision_predict.swift"
        run = subprocess.run(["swift", str(script), str(package)] + [str(p) for p in small], capture_output=True, text=True)
        if run.returncode != 0:
            report["vision_against_pillow"] = {"held": False, "error": run.stderr.strip()[-600:]}
        else:
            seen = {json.loads(line)["file"]: json.loads(line)["probabilities"] for line in run.stdout.splitlines() if line.startswith("{")}
            vision = np.stack([[seen[p.name][label] for label in labels] for p in small])
            by_filter = {}
            for name, resample in FILTERS.items():
                pillow = torch_probabilities(model, [chip(image, resample) for image in with_photos])
                d = np.abs(pillow - vision)
                by_filter[name] = {"largest_probability_difference": round(float(d.max()), 4), "mean_of_the_largest_per_photograph": round(float(d.max(1).mean()), 4),
                                   "top_class_agrees_on": int((pillow.argmax(1) == vision.argmax(1)).sum())}
            closest = min(by_filter, key=lambda k: by_filter[k]["mean_of_the_largest_per_photograph"])
            report["vision_against_pillow"] = {"photographs": len(small), "top_probability_of_each": [round(float(v), 3) for v in vision.max(1)],
                                               "by_pillow_filter": by_filter, "closest_filter": closest, "held": True}
    else:
        report["vision_against_pillow"] = {"held": None, "skipped": f"no photographs in {args.photos}"}

    (OUT / "export_smoke.json").write_text(json.dumps(report, indent=1) + "\n")
    print(json.dumps(report, indent=1))
    held = report["core_ml_against_pytorch"]["held"] and report["vision_against_pillow"]["held"] is not False and report["converted"]["metadata_reads_back"]
    print("the export chain held" if held else "the export chain did NOT hold")
    return 0 if held else 1


if __name__ == "__main__":
    sys.exit(main())
