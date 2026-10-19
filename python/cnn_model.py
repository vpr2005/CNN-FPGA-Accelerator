"""
-----------------------------------------------------------------------------
File: cnn_model.py
Description: Bit-accurate Python reference model of the FPGA CNN Accelerator.
             Mirrors the exact hardware arithmetic, fixed-point quantization,
             ReLU scaling, 2x2 max pooling, and FC matrix multiplication.
-----------------------------------------------------------------------------
"""

import numpy as np

class CNNHardwareModel:
    def __init__(self, num_filters=4, img_w=28, img_h=28, shift_bits=7, num_classes=10):
        self.num_filters = num_filters
        self.img_w = img_w
        self.img_h = img_h
        self.shift_bits = shift_bits
        self.num_classes = num_classes
        
        self.conv_out_w = img_w - 2  # 26
        self.conv_out_h = img_h - 2  # 26
        self.pool_out_w = self.conv_out_w // 2  # 13
        self.pool_out_h = self.conv_out_h // 2  # 13
        self.num_features = self.pool_out_w * self.pool_out_h  # 169

        # Weights and biases (signed INT8 / INT32)
        self.conv_weights = np.zeros((num_filters, 3, 3), dtype=np.int8)
        self.conv_biases  = np.zeros((num_filters,), dtype=np.int32)
        
        # FC weights: shape [num_classes, num_features, num_filters]
        self.fc_weights = np.zeros((num_classes, self.num_features, num_filters), dtype=np.int8)
        self.fc_biases  = np.zeros((num_classes,), dtype=np.int32)

    def set_weights(self, conv_w, conv_b, fc_w, fc_b):
        self.conv_weights = conv_w.astype(np.int8)
        self.conv_biases  = conv_b.astype(np.int32)
        self.fc_weights   = fc_w.astype(np.int8)
        self.fc_biases    = fc_b.astype(np.int32)

    def conv2d_relu(self, img):
        """
        Bit-accurate 2D Convolution with 3x3 kernel, valid padding, and ReLU scaling.
        Input img: [28, 28] int8
        Output: [num_filters, 26, 26] int8 in range [0, 127]
        """
        out = np.zeros((self.num_filters, self.conv_out_h, self.conv_out_w), dtype=np.int8)
        
        for f in range(self.num_filters):
            kernel = self.conv_weights[f].astype(np.int32)
            bias   = int(self.conv_biases[f])
            
            for r in range(self.conv_out_h):
                for c in range(self.conv_out_w):
                    patch = img[r:r+3, c:c+3].astype(np.int32)
                    dot = np.sum(patch * kernel) + bias
                    
                    # ReLU
                    relu_val = max(0, dot)
                    
                    # Arithmetic Right Shift
                    shifted = relu_val >> self.shift_bits
                    
                    # Clamping to [0, 127]
                    clamped = min(127, max(0, shifted))
                    out[f, r, c] = np.int8(clamped)
                    
        return out

    def maxpool2d(self, feat_maps):
        """
        Streaming 2x2 Max Pooling with Stride 2.
        Input: [num_filters, 26, 26]
        Output: [num_filters, 13, 13]
        """
        out = np.zeros((self.num_filters, self.pool_out_h, self.pool_out_w), dtype=np.int8)
        
        for f in range(self.num_filters):
            for pr in range(self.pool_out_h):
                for pc in range(self.pool_out_w):
                    window = feat_maps[f, pr*2:(pr*2)+2, pc*2:(pc*2)+2]
                    out[f, pr, pc] = np.max(window)
                    
        return out

    def fully_connected(self, pooled_maps):
        """
        Fully Connected Matrix-Vector Multiplier.
        Input pooled_maps: [num_filters, 13, 13]
        Output: logits [10] int32, predicted_class int
        """
        logits = np.zeros(self.num_classes, dtype=np.int32)
        
        # Flatten spatial dimensions in raster order to match hardware address generator
        # Feature RAM stores at addr = pr * 13 + pc: [ch0, ch1, ch2, ch3]
        for c in range(self.num_classes):
            accum = int(self.fc_biases[c])
            for s in range(self.num_features):
                pr = s // self.pool_out_w
                pc = s % self.pool_out_w
                
                for ch in range(self.num_filters):
                    feat = int(pooled_maps[ch, pr, pc])
                    w = int(self.fc_weights[c, s, ch])
                    accum += feat * w
                    
            logits[c] = accum
            
        pred_class = int(np.argmax(logits))
        max_score = int(logits[pred_class])
        return logits, pred_class, max_score

    def forward(self, img):
        """Full inference pipeline"""
        conv_out = self.conv2d_relu(img)
        pool_out = self.maxpool2d(conv_out)
        logits, pred_class, max_score = self.fully_connected(pool_out)
        return {
            'conv_out': conv_out,
            'pool_out': pool_out,
            'logits': logits,
            'predicted_class': pred_class,
            'max_score': max_score
        }
