'''plist utility functions'''

from Foundation import NSPropertyListSerialization
from Foundation import NSPropertyListXMLFormat_v1_0
from Foundation import NSPropertyListBinaryFormat_v1_0

class FoundationPlistException(Exception):
    """Basic exception for plist errors"""
    pass


def write_plist(dataObject, pathname=None, plist_format=None):
    '''
    Write 'rootObject' as a plist to pathname or return as a string.
    '''
    if plist_format == 'binary':
        plist_format = NSPropertyListBinaryFormat_v1_0
    else:
        plist_format = NSPropertyListXMLFormat_v1_0
    
    plistData, error = (
        NSPropertyListSerialization.
        dataFromPropertyList_format_errorDescription_(
            dataObject, plist_format, None))
    if plistData is None:
        if error:
            error = error.encode('ascii', 'ignore')
        else:
            error = "Unknown error"
        raise FoundationPlistException(error)
    if pathname:
        if plistData.writeToFile_atomically_(pathname, True):
            return
        else:
            raise FoundationPlistException(
                "Failed to write plist data to %s" % filepath)
    else:
        return plistData
