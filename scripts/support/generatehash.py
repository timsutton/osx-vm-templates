#!/usr/bin/python

import sys
import shadowhash
import base64

if __name__ == "__main__":
    if len(sys.argv) == 2:
        hash = shadowhash.generate(sys.argv[1])
        print base64.b64encode(hash)
