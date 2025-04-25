import os 
import json
import numpy as np
import cv2
import matplotlib.pyplot as plt

from segment_anything import sam_model_registry, SamAutomaticMaskGenerator


def load_capture(folder):
    #Load RGP image
    img_path = os.path.join(folder, 'frame.jpg')
    img = cv2.imread(img_path)
    #ensure hxwx3 uint8 numpy array
    img = np.asarray(img, dtype=np.uint8)
    assert img is not None, f"Cannot read image from {img_path}"

    #Load metadata
    meta = json.load(open(os.path.join(folder, 'meta.json'), "r"))
    intr = np.array(meta["intrinsics"], dtype=np.float32)

    #load depth.bin as float32 array
    depth_flat = np.fromfile(os.path.join(folder, "depth.bin"), dtype=np.float32)

    #Reshap to (H,W). On iPhone14Pro ARKit uses 256×192 by default
    H, W = 192, 256
    assert depth_flat.size == H * W, f"Unexpected depth size: {depth_flat.size}"
    depth = depth_flat.reshape((H, W))
    
    return img, depth, intr

def segment_and_measure(img, depth, intrinsics,
                        checkpoint="sam_vit_h_4b8939.pth"):
    # 1) Convert to RGB for SAM
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # 2) Run AutomaticMaskGenerator
    sam = sam_model_registry["vit_h"](checkpoint=checkpoint)
    mask_gen = SamAutomaticMaskGenerator(sam)
    masks = mask_gen.generate(rgb)
    if not masks:
        raise RuntimeError("SAM found no masks!")

    H_img, W_img = img.shape[:2]
    img_area = H_img * W_img

    # 3) Looser area thresholds
    min_area = 0.005 * img_area   # at least 0.5%
    max_area = 0.30  * img_area   # at most 30%

    candidates = []
    for m in masks:
        A = m["area"]
        if not (min_area < A < max_area):
            continue

        x, y, w, h = m["bbox"]
        rect_area = w * h
        if rect_area <= 0:
            continue

        rect_score = m["area"] / rect_area
        asp    = w / float(h)   # aspect ratio

        # require roughly rectangular shape
        if rect_score < 0.4:    # at least 40% of its bounding‐box
            continue
        # require a plausible box aspect ratio (say between 0.5 and 3.0)
        if not (0.5 < asp < 3.0):
            continue

        # use a combined score: area × rectangularity
        candidates.append((A * rect_score, m))

    if candidates:
        # pick the highest‐scoring mask
        best = max(candidates, key=lambda p: p[0])[1]
    else:
        # — FALLBACK: contour‐based rectangle detection —
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        blur = cv2.GaussianBlur(gray, (5,5), 0)
        edges = cv2.Canny(blur, 50, 150)
        cnts, _ = cv2.findContours(edges, cv2.RETR_LIST,
                                   cv2.CHAIN_APPROX_SIMPLE)

        rects = []
        for c in cnts:
            peri = cv2.arcLength(c, True)
            approx = cv2.approxPolyDP(c, 0.02 * peri, True)
            if len(approx) == 4 and cv2.isContourConvex(approx):
                x, y, w, h = cv2.boundingRect(approx)
                A = w*h
                if min_area < A < max_area:
                    rects.append((A, (x,y,w,h)))
        if not rects:
            raise RuntimeError("No box found via SAM _or_ contours.")
        # pick the largest contour‐box
        _, (x,y,w,h) = max(rects, key=lambda p: p[0])
        # Build a dummy mask
        dummy = np.zeros((H_img, W_img), dtype=bool)
        dummy[y:y+h, x:x+w] = True
        best = {"bbox": [x,y,w,h], "segmentation": dummy}

    # 4) Resize mask to depth resolution
    mask = best["segmentation"].astype(np.uint8)
    mask_resized = cv2.resize(mask, (depth.shape[1], depth.shape[0]),
                              interpolation=cv2.INTER_NEAREST).astype(bool)

    # 5) Pull out median depth under the mask
    depth_vals = depth[mask_resized]
    z = float(np.median(depth_vals))

    # 6) Optionally reproject to 3D Euclidean distance
    fx, _, cx = intrinsics[0]
    _, fy, cy = intrinsics[1]
    u = int((best["bbox"][0] + best["bbox"][2]/2) * depth.shape[1]/W_img)
    v = int((best["bbox"][1] + best["bbox"][3]/2) * depth.shape[0]/H_img)
    x_cam = (u - cx) * z / fx
    y_cam = (v - cy) * z / fy
    radial = np.sqrt(x_cam**2 + y_cam**2 + z**2)

    return best["bbox"], z, radial


def draw_and_show(img, bbox, distance, dims_m, out_path="out_bbox.png"):
    x,y,w,h = bbox
    #draw a green box
    vis = img.copy()
    cv2.rectangle(vis, (x,y), (x+w,y+h), (0,255,0), 2)
    label = f"{distance:.2f} m, {dims_m[0]:.2f}×{dims_m[1]:.2f} m"
    cv2.putText(vis, label, (x, max(20,y-10)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0,255,0), 2)


    # Show with Matplotlib (RGB)
    plt.figure(figsize=(8,6))
    plt.imshow(cv2.cvtColor(vis, cv2.COLOR_BGR2RGB))
    plt.axis("off")
    plt.title("Detected Box")
    plt.show()

    # Save to disk
    cv2.imwrite(out_path, vis)
    print(f"Annotated image saved to {out_path}")


def main():
    folder = "captures/sample_capture"   
    img, depth, intr = load_capture(folder)

    (x,y,w,h), dist, (w_m, h_m) = segment_and_measure(img, depth, intr)

    print(f"Box bbox (px): x={x}, y={y}, w={w}, h={h}")
    print(f"Distance from camera: {dist:.2f} m")
    print(f"Real‑world size: {w_m:.2f} m × {h_m:.2f} m")

    draw_and_show(img, (x,y,w,h), dist, (w_m,h_m))

if __name__ == "__main__":
    main()