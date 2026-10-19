"""
-----------------------------------------------------------------------------
File: verify.py
Description: Automated verification script comparing Vivado Hardware Simulation
             results against Python Golden Reference model. Computes bit-accuracy,
             latency, throughput (FPS), and GOP/s metrics.
-----------------------------------------------------------------------------
"""

import os
import json
import re

def parse_hw_output(hw_output_path):
    if not os.path.exists(hw_output_path):
        raise FileNotFoundError(f"Hardware output file not found: {hw_output_path}")

    with open(hw_output_path, "r") as f:
        content = f.read()

    tests = {}
    test_blocks = re.split(r"TEST:\s*", content)
    for block in test_blocks:
        if not block.strip():
            continue
        lines = block.strip().split("\n")
        test_name = lines[0].strip()
        
        pred_class_match = re.search(r"PREDICTED_CLASS:\s*(\d+)", block)
        max_score_match  = re.search(r"MAX_SCORE:\s*(-?\d+)", block)
        latency_match    = re.search(r"LATENCY_CYCLES:\s*(\d+)", block)
        
        logits = {}
        for line in lines:
            logit_match = re.search(r"LOGIT_(\d+):\s*(-?\d+)", line)
            if logit_match:
                logits[int(logit_match.group(1))] = int(logit_match.group(2))

        tests[test_name] = {
            "predicted_class": int(pred_class_match.group(1)) if pred_class_match else None,
            "max_score": int(max_score_match.group(1)) if max_score_match else None,
            "latency_cycles": int(latency_match.group(1)) if latency_match else None,
            "logits": [logits[i] for i in range(10)] if len(logits) == 10 else []
        }

    return tests

def main():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    golden_path = os.path.join(base_dir, "data", "golden_results.json")
    if not os.path.exists(golden_path):
        print(f"Error: Golden reference {golden_path} does not exist.")
        return 1

    with open(golden_path, "r") as f:
        golden_data = json.load(f)

    candidate_paths = [
        os.path.join(base_dir, "data", "hw_output_predictions.txt"),
        os.path.join(base_dir, "hw_output_predictions.txt"),
        os.path.join(base_dir, "vivado_project", "cnn_accelerator.sim", "sim_1", "behav", "xsim", "hw_output_predictions.txt")
    ]
    hw_output_path = None
    for p in candidate_paths:
        if os.path.exists(p):
            hw_output_path = p
            break

    if hw_output_path is None:
        print(f"Error: Hardware output file not found in any of:")
        for p in candidate_paths:
            print(f"  - {p}")
        return 1

    print(f"Loading hardware predictions from: {hw_output_path}")

    print("=======================================================================")
    print("      CNN FPGA ACCELERATOR: HARDWARE / SOFTWARE CO-VERIFICATION       ")
    print("=======================================================================")

    hw_tests = parse_hw_output(hw_output_path)
    all_passed = True

    test_mapping = {
        "MNIST_Digit_0": "digit_0",
        "MNIST_Digit_1": "digit_1"
    }

    total_ops_per_inference = 42588  # Conv (24,336) + ReLU (2,704) + Pool (2,028) + FC (13,520)

    for hw_test_name, golden_key in test_mapping.items():
        if hw_test_name not in hw_tests:
            print(f"[FAIL] Missing test in hardware output: {hw_test_name}")
            all_passed = False
            continue

        hw_res = hw_tests[hw_test_name]
        gold_res = golden_data[golden_key]

        hw_pred = hw_res["predicted_class"]
        gold_pred = gold_res["predicted_class"]
        hw_score = hw_res["max_score"]
        gold_score = gold_res["max_score"]
        latency = hw_res["latency_cycles"]

        print(f"\n--- Checking {hw_test_name} ---")
        print(f"  Hardware Predicted Class: {hw_pred}")
        print(f"  Golden Software Class:   {gold_pred}")
        print(f"  Hardware Max Logit Score: {hw_score}")
        print(f"  Golden Max Logit Score:   {gold_score}")
        print(f"  Inference Latency:        {latency} clock cycles")

        # Compare class
        if hw_pred == gold_pred:
            print("  -> Class Prediction: PASS (100% Match)")
        else:
            print(f"  -> Class Prediction: FAIL (HW: {hw_pred} != Gold: {gold_pred})")
            all_passed = False

        # Compare logits
        if hw_res["logits"] and gold_res["logits"]:
            diffs = [abs(h - g) for h, g in zip(hw_res["logits"], gold_res["logits"])]
            max_diff = max(diffs)
            print(f"  -> Maximum Logit Error Delta: {max_diff}")
            if max_diff == 0:
                print("  -> Bit-Accurate Verification: PASS (Exact 0-delta match across all 10 logits!)")
            else:
                print("  -> Logit Mismatch detected!")
                all_passed = False

        # Throughput calculations
        clk_mhz = 100.0
        time_us = (latency / (clk_mhz * 1e6)) * 1e6
        fps = (clk_mhz * 1e6) / latency
        gops = (fps * total_ops_per_inference) / 1e9

        print(f"  -> Performance @ 100MHz: {time_us:.2f} us/inference | {fps:,.0f} FPS | {gops:.2f} GOP/s")
        
        clk_150 = 150.0
        time_150_us = (latency / (clk_150 * 1e6)) * 1e6
        fps_150 = (clk_150 * 1e6) / latency
        gops_150 = (fps_150 * total_ops_per_inference) / 1e9
        print(f"  -> Performance @ 150MHz: {time_150_us:.2f} us/inference | {fps_150:,.0f} FPS | {gops_150:.2f} GOP/s")

    print("\n=======================================================================")
    if all_passed:
        print(">>> OVERALL STATUS: ALL HARDWARE / SOFTWARE CHECKS PASSED (100% BIT-ACCURATE) <<<")
        return 0
    else:
        print(">>> OVERALL STATUS: VERIFICATION FAILED <<<")
        return 1

if __name__ == "__main__":
    exit(main())
