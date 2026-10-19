"""
-----------------------------------------------------------------------------
File: generate_test_vectors.py
Description: Generates quantized weights, biases, and test input images for
             the FPGA CNN accelerator, formatted as .mem hex files for SystemVerilog
             $readmemh simulation and synthesis.
-----------------------------------------------------------------------------
"""

import os
import json
import numpy as np
from cnn_model import CNNHardwareModel

def to_hex_8(val):
    """Convert signed 8-bit int (-128..127) to 2-char hex string"""
    v = int(val) & 0xFF
    return f"{v:02X}"

def to_hex_32(val):
    """Convert signed 32-bit int to 8-char hex string"""
    v = int(val) & 0xFFFFFFFF
    return f"{v:08X}"

def create_synthetic_digit(digit=0, w=28, h=28):
    """Generates synthetic digit patterns (values 0..100)"""
    img = np.zeros((h, w), dtype=np.int8)
    
    if digit == 0:
        # Oval loop
        for r in range(6, 22):
            for c in range(6, 22):
                dr = (r - 14) / 7.0
                dc = (c - 14) / 6.0
                dist = dr*dr + dc*dc
                if 0.6 <= dist <= 1.2:
                    img[r, c] = 80
    elif digit == 1:
        # Vertical stroke
        for r in range(5, 23):
            for c in range(13, 16):
                img[r, c] = 95
        # Top serif
        img[6, 11:13] = 70
        img[7, 12] = 80
        # Bottom base
        img[22, 10:19] = 80
    elif digit == 7:
        # Top bar
        img[6:8, 8:20] = 90
        # Diagonal stroke
        for i in range(14):
            r = 8 + i
            c = 19 - int(i * 0.7)
            if 0 <= r < h and 0 <= c < w:
                img[r, c-1:c+1] = 90
    else:
        # Cross pattern
        img[14, 6:22] = 85
        img[6:22, 14] = 85
        
    return img

def main():
    data_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data"))
    os.makedirs(data_dir, exist_ok=True)
    
    np.random.seed(42)
    
    num_filters = 4
    img_w, img_h = 28, 28
    num_classes = 10
    num_features = 169
    
    # 1. Initialize CNN model
    model = CNNHardwareModel(
        num_filters=num_filters,
        img_w=img_w,
        img_h=img_h,
        shift_bits=7,
        num_classes=num_classes
    )
    
    # 2. Design standard edge/feature detection kernels for 4 filters
    # Filter 0: Horizontal Sobel-like edge
    # Filter 1: Vertical Sobel-like edge
    # Filter 2: Diagonal / Corner
    # Filter 3: Center-surround Laplacian
    conv_w = np.zeros((num_filters, 3, 3), dtype=np.int8)
    conv_w[0] = np.array([[-1, -2, -1],
                          [ 0,  0,  0],
                          [ 1,  2,  1]], dtype=np.int8) * 8
    
    conv_w[1] = np.array([[-1,  0,  1],
                          [-2,  0,  2],
                          [-1,  0,  1]], dtype=np.int8) * 8
                          
    conv_w[2] = np.array([[ 2,  1,  0],
                          [ 1,  0, -1],
                          [ 0, -1, -2]], dtype=np.int8) * 8
                          
    conv_w[3] = np.array([[ 0,  1,  0],
                          [ 1, -4,  1],
                          [ 0,  1,  0]], dtype=np.int8) * 12

    conv_b = np.array([16, 16, 20, 24], dtype=np.int32)
    
    # 3. Design Fully Connected weights (10 classes x 169 features x 4 channels)
    fc_w = np.random.randint(-15, 16, size=(num_classes, num_features, num_filters), dtype=np.int8)
    fc_b = np.array([-50, 120, -30, 40, -10, 60, -20, 80, -40, 10], dtype=np.int32)
    
    # Boost class 1 weights for vertical feature (filter 1) in center columns
    # so digit 1 confidently activates class 1!
    for s in range(num_features):
        pc = s % 13
        if 5 <= pc <= 7:
            fc_w[1, s, 1] = 45
            
    # Boost class 0 weights for loop features
    for s in range(num_features):
        pr = s // 13
        pc = s % 13
        if pr in [2, 3, 9, 10] or pc in [2, 3, 9, 10]:
            fc_w[0, s, 0] = 30
            fc_w[0, s, 1] = 30

    model.set_weights(conv_w, conv_b, fc_w, fc_b)
    
    # 4. Write conv_weights.mem
    conv_w_path = os.path.join(data_dir, "conv_weights.mem")
    with open(conv_w_path, "w") as f:
        for flt in range(num_filters):
            f.write(f"// Filter {flt}\n")
            for r in range(3):
                for c in range(3):
                    f.write(f"{to_hex_8(conv_w[flt, r, c])}\n")
    print(f"Generated: {conv_w_path}")

    # 5. Write conv_biases.mem
    conv_b_path = os.path.join(data_dir, "conv_biases.mem")
    with open(conv_b_path, "w") as f:
        for flt in range(num_filters):
            f.write(f"{to_hex_32(conv_b[flt])}\n")
    print(f"Generated: {conv_b_path}")

    # 6. Write fc_weights.mem
    # Format per entry: {w3, w2, w1, w0} -> 32-bit hex
    fc_w_path = os.path.join(data_dir, "fc_weights.mem")
    with open(fc_w_path, "w") as f:
        for c in range(num_classes):
            f.write(f"// Class {c}\n")
            for s in range(num_features):
                w0 = to_hex_8(fc_w[c, s, 0])
                w1 = to_hex_8(fc_w[c, s, 1])
                w2 = to_hex_8(fc_w[c, s, 2])
                w3 = to_hex_8(fc_w[c, s, 3])
                f.write(f"{w3}{w2}{w1}{w0}\n")
    print(f"Generated: {fc_w_path}")

    # 7. Write fc_biases.mem
    fc_b_path = os.path.join(data_dir, "fc_biases.mem")
    with open(fc_b_path, "w") as f:
        for c in range(num_classes):
            f.write(f"{to_hex_32(fc_b[c])}\n")
    print(f"Generated: {fc_b_path}")

    # 8. Generate sample test images (digit 0 and digit 1)
    digits = [0, 1]
    golden_results = {}
    
    for d in digits:
        img = create_synthetic_digit(digit=d)
        img_path = os.path.join(data_dir, f"input_image_{d}.mem")
        with open(img_path, "w") as f:
            for r in range(img_h):
                for c in range(img_w):
                    f.write(f"{to_hex_8(img[r, c])}\n")
        print(f"Generated test image: {img_path}")
        
        # Run golden software forward pass
        result = model.forward(img)
        print(f"Digit {d} Ground Truth: Predicted Class = {result['predicted_class']}, Max Score = {result['max_score']}")
        print(f"Logits = {result['logits'].tolist()}")
        
        golden_results[f"digit_{d}"] = {
            "predicted_class": int(result['predicted_class']),
            "max_score": int(result['max_score']),
            "logits": [int(x) for x in result['logits']],
            "conv_min": int(np.min(result['conv_out'])),
            "conv_max": int(np.max(result['conv_out'])),
            "pool_min": int(np.min(result['pool_out'])),
            "pool_max": int(np.max(result['pool_out']))
        }
        
    golden_path = os.path.join(data_dir, "golden_results.json")
    with open(golden_path, "w") as f:
        json.dump(golden_results, f, indent=2)
    print(f"Generated: {golden_path}")

if __name__ == "__main__":
    main()
