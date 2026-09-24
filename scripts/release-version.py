#!/usr/bin/env python3
"""Map a stable vMAJOR.MINOR.PATCH tag to a monotonic CFBundleVersion."""
import re
import sys

match = re.fullmatch(r"v(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})", sys.argv[1] if len(sys.argv) == 2 else "")
if not match:
    sys.exit("Expected vMAJOR.MINOR.PATCH, with each component between 0 and 999")
major, minor, patch = map(int, match.groups())
build = major * 1_000_000 + minor * 1_000 + patch
if build == 0:
    sys.exit("Release version must be newer than 0.0.0")
print(f"MICLINE_VERSION={major}.{minor}.{patch}")
print(f"MICLINE_BUILD_NUMBER={build}")
