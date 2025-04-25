import numpy as np
import matplotlib.pyplot as plt

# ARKit LiDAR depthMap is 256×192 (width×height)
W, H = 256, 192  

# 1. Load the flat float32 array
depth = np.fromfile("captures/sample_capture/depth.bin", dtype=np.float32)

# 2. Reshape into (H, W)
depth = depth.reshape((H, W))

# 3. Visualize
plt.figure(figsize=(6, 5))
plt.title("LiDAR Depth (meters)")
plt.imshow(depth, cmap="viridis", origin="upper")
plt.colorbar(label="Distance (m)")
plt.show()
