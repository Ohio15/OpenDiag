#!/usr/bin/env python3
"""openobd launcher (also the PyInstaller entry point)."""
import sys

from openobd.app import main

if __name__ == "__main__":
    sys.exit(main())
