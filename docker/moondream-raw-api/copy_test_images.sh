#!/bin/bash

# Copy test images from rapidocr-raw-api
echo "Copying test images from rapidocr-raw-api..."
cp -r ../rapidocr-raw-api/test_images ./
echo "Test images copied successfully!"
ls -la test_images/