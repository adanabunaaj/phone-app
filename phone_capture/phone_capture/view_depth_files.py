import numpy as np
import matplotlib.pyplot as plt

# 1. Adjust these to whatever your capture’s resolution is:
H, W = 480, 640    

# 2. Load the floats
depth = np.fromfile("depth.bin", dtype=np.float32)
depth = depth.reshape((H, W))  # row‑major

# 3. Visualize
plt.figure(figsize=(6, 5))
plt.title("Depth Map (meters)")
plt.imshow(depth, cmap="viridis")
plt.colorbar(label="Depth (m)")
plt.show()

# 4. (Optional) Save as a PNG for easy browsing
#    This will linearly map your depth values to [0–255].
depth_norm = (depth - depth.min()) / (depth.max() - depth.min())
import imageio
imageio.imwrite("depth.bin", (depth_norm * 255).astype(np.uint8))
print("Wrote depth.png")
