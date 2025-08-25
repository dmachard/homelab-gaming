#!/bin/bash

PYTHON_SCRIPT="/home/user/console/vm-gpu.py"
VM_NAME="win10"

/usr/bin/python3 "$PYTHON_SCRIPT" stop --vm-name "$VM_NAME"
