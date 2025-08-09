#!/bin/bash

# Script to download RapidOCR models from official sources
# These are actual URLs for RapidOCR ONNX models

MODEL_DIR="./models/rapidocr"

echo "========================================="
echo "RapidOCR Model Downloader"
echo "========================================="
echo ""

echo "Creating model directory..."
mkdir -p "$MODEL_DIR"

cd "$MODEL_DIR" || exit 1

# GitHub release base URL for RapidOCR models
BASE_URL="https://github.com/RapidAI/RapidOCR/releases/download"

# Model versions (update these as needed)
DET_VERSION="v1.1.0"
REC_VERSION="v1.0.0"
CLS_VERSION="v1.0.0"

echo "Downloading RapidOCR ONNX models..."
echo ""

# Detection model - for text region detection
DET_MODEL="ch_PP-OCRv3_det_infer.onnx"
if [ ! -f "$DET_MODEL" ]; then
    echo "Downloading detection model..."
    # Try the mobile version which is smaller and faster
    wget -q --show-progress "https://github.com/RapidAI/RapidOCR/releases/download/v1.1.0/ch_ppocr_mobile_v2.0_det_infer.onnx" -O ch_ppocr_mobile_v2.0_det_infer.onnx || {
        echo "Failed to download detection model from GitHub releases."
        echo "You can manually download from: https://github.com/RapidAI/RapidOCR/releases"
    }
else
    echo "Detection model already exists: $DET_MODEL"
fi

# Recognition model - for text recognition
REC_MODEL="ch_PP-OCRv3_rec_infer.onnx"
if [ ! -f "$REC_MODEL" ]; then
    echo "Downloading recognition model..."
    # Try the mobile version
    wget -q --show-progress "https://github.com/RapidAI/RapidOCR/releases/download/v1.1.0/ch_ppocr_mobile_v2.0_rec_infer.onnx" -O ch_ppocr_mobile_v2.0_rec_infer.onnx || {
        echo "Failed to download recognition model from GitHub releases."
        echo "You can manually download from: https://github.com/RapidAI/RapidOCR/releases"
    }
else
    echo "Recognition model already exists: $REC_MODEL"
fi

# Classification model - for text angle classification
CLS_MODEL="ch_ppocr_mobile_v2.0_cls_infer.onnx"
if [ ! -f "$CLS_MODEL" ]; then
    echo "Downloading classification model..."
    wget -q --show-progress "https://github.com/RapidAI/RapidOCR/releases/download/v1.1.0/ch_ppocr_mobile_v2.0_cls_infer.onnx" -O ch_ppocr_mobile_v2.0_cls_infer.onnx || {
        echo "Failed to download classification model from GitHub releases."
        echo "You can manually download from: https://github.com/RapidAI/RapidOCR/releases"
    }
else
    echo "Classification model already exists: $CLS_MODEL"
fi

echo ""
echo "Alternative: Using Hugging Face Models"
echo "---------------------------------------"

# Alternative: Download from Hugging Face (if GitHub fails)
if [ ! -f "ch_PP-OCRv4_det_infer.onnx" ]; then
    echo "You can also download PP-OCRv4 models from Hugging Face:"
    echo "  Detection: https://huggingface.co/SWHL/RapidOCR/blob/main/models/ch_PP-OCRv4_det_infer.onnx"
    echo "  Recognition: https://huggingface.co/SWHL/RapidOCR/blob/main/models/ch_PP-OCRv4_rec_infer.onnx"
    echo ""
    
    # Uncomment to download from Hugging Face
    # wget -q --show-progress "https://huggingface.co/SWHL/RapidOCR/resolve/main/models/ch_PP-OCRv4_det_infer.onnx" -O ch_PP-OCRv4_det_infer.onnx
    # wget -q --show-progress "https://huggingface.co/SWHL/RapidOCR/resolve/main/models/ch_PP-OCRv4_rec_infer.onnx" -O ch_PP-OCRv4_rec_infer.onnx
fi

echo ""
echo "Models directory contents:"
echo "--------------------------"
ls -lah "$MODEL_DIR"

echo ""
echo "========================================="
echo "Model Download Complete"
echo "========================================="
echo ""
echo "Notes:"
echo "1. The container will automatically use models from this directory"
echo "2. If models are not found, the container will try to extract them from the package"
echo "3. You can place custom ONNX models here with names containing 'det', 'rec', or 'cls'"
echo ""
echo "Supported model naming patterns:"
echo "  - *det*.onnx for detection models"
echo "  - *rec*.onnx for recognition models"
echo "  - *cls*.onnx for classification models"
echo ""
echo "To use these models:"
echo "  docker-compose up --build"