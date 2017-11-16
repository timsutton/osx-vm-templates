'''Functions for generating ShadowHashData'''

import hashlib

import arc4random
import pbkdf2

import plistutils


def make_salt(saltlen):
    '''Generate a random salt'''
    salt = ''
    for char in arc4random.randsample(0, 255, saltlen):
        salt += chr(char)
    return salt


def generate(password):
    '''Generate a ShadowHashData structure as used by macOS 10.8+'''
    iterations = arc4random.randrange(30000, 50000)
    salt = make_salt(32)
    keylen = 128
    try:
        entropy = hashlib.pbkdf2_hmac(
            'sha512', password, salt, iterations, dklen=keylen)
    except AttributeError:
        # old Python, do it a different way
        entropy = pbkdf2.pbkdf2_bin(
            password, salt, iterations=iterations, keylen=keylen,
            hashfunc=hashlib.sha512)

    data = {'SALTED-SHA512-PBKDF2': {'entropy': buffer(entropy),
                                     'iterations': iterations,
                                     'salt': buffer(salt)},
                       }
    return plistutils.write_plist(data, plist_format='binary')
