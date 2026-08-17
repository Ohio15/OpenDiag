"""Enable `python -m openobd` to launch the GUI."""
import sys

from .app import main

if __name__ == "__main__":
    sys.exit(main())
