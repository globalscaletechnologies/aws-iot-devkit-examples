#!/usr/bin/python

import sys

try:
    from bcrypt import hashpw, gensalt
except ImportError:
    print "[!] Error importing 'bcrypt': %s" % err
    sys.exit()

DEFAULT_ROUNDS = 10

def main():
    if len(sys.argv) < 2:
        usage()

    hashed_password = hashpw(sys.argv[1], gensalt(DEFAULT_ROUNDS))
    print "%s" % hashed_password

def usage():
    print "Usage: %s <password>" % sys.argv[0]
    sys.exit(0)


if __name__ == '__main__':
    main()
