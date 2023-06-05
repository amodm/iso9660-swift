# ISO9660
Read/write ISO9660 (CD, DVD) images, with a pure Swift API. The latest spec this supports is [ECMA-119 4th edition, June 2019](https://www.ecma-international.org/wp-content/uploads/ECMA-119_4th_edition_june_2019.pdf).

## Overview

Optical media use the [ISO 9660](https://en.wikipedia.org/wiki/ISO_9660) format to store their contents, along with related auxiliary standards such as Joliet extension, [System Use Sharing Protocol](https://studylib.net/doc/18849138/ieee-p1281-system-use-sharing-protocol-draft) and [Rock Ridge](https://web.archive.org/web/20170404043745/http://www.ymi.com/ymi/sites/default/files/pdf/Rockridge.pdf).

This library provides a pure-Swift API that runs in the user-space to directly access and manipulate ISO images, without the need for mounting such images.

### Reading ISO images

```swift
import Foundation
import ISO9660

// create media
let media = try! ISOImageFileMedia("cdimage.iso")

// create a filesystem object using this media
let fs = try! ISOFileSystem(media)

// access root directory and list its children
let dir = try! fs.getFSEntry("/")
for child in try fs.list(directory: directory) {
    print(child.name)
}

// get input stream to a file
let file = try! fs.getFSEntry("/some/file/of/mine")
let inputStream = try! fs.readFile(file)
defer {
    inputStream.close()
}
while inputStream.hasBytesAvailable {
    // do something
}
```

### Writing ISO images

```swift
import Foundation
import ISO9660

let folderRoot = "path/to/data"

// create media
let media = try! ISOImageFileMedia("cdimage.iso", readonly: false)

// prepare write options
let writeOptions = ISOWriter.WriteOptions(volumeIdentifier: "MYDATA")

// prepare writer - the last parameter is a closure that returns an `InputStream`
// to the file referenced by `path`
let writer = ISOWriter(media: media, options: writeOptions) { path in
    let localPath = "\(folderRoot)\(path)"
    return InputStream(fileAtPath: localPath)!
}

// add a file
let volPath = "/boot/grub.cfg"
let localPath = "\(folderRoot)\(volPath)"
let fileSize = try! FileManager.default.attributesOfItem(atPath: localPath)[.size] as! UInt64
try! writer.addFile(path: volPath, size: fileSize, metadata: nil)

// write 
try! writer.writeAndClose()
```

## Specification

The technical details of ISO 9660 specification are specified under [ECMA-119](https://www.ecma-international.org/wp-content/uploads/ECMA-119_4th_edition_june_2019.pdf). This is not needed to do usual reading/writing, but this section can be useful to folks trying to
understand things under the hood.

At a high level, the following important concepts need to be understood:

* **Physical Storage**: ISO 9660 images can exist in optical media such as CD/DVD etc, but these days can mostly be seen being distributed as `.iso` files. More details can be found in ``ISOImageMedia``, which acts as the abstraction later for the physical media. ``ISOImageFileMedia`` is the concrete implementation for `.iso` files.

* **Logical Blocks**: The ISO 9660 filesystem uses an LBA (Logical Block Addressing) scheme, i.e. addresses (e.g. location of a file) are mentioned in terms of logical block numbers, so if a file has a starting address of `1000`, it means the byte address is `1000 * 2048` bytes (assuming a block size of 2048 bytes), and not `1000`. The block size is defined inside a Volume Descriptor.

* **Volume Descriptors**: These describe the top level information about a volume, and show up as a series of descriptors after the first 16 sectors. See ``VolumeDescriptor`` for different kinds of descriptors. The most important ones are ``VolumeDescriptor/primary``, ``VolumeDescriptor/supplementary``, and ``VolumeDescriptor/enhanced`` types, because they describe the directory structure stored inside the volume via ``VolumeDirectoryDescriptor``.

* **Directory Tree**: The directory tree is represented via two different structures:
  1. **Directory Records**: For every file/directory stored in an ISO filesystem has a ``DirectoryRecord`` structure describing itself. Starting from ``VolumeDirectoryDescriptor/rootDirectory``, one can traverse a path tree jumping to different ``DirectoryRecord``s to reach the one we need.
  2. **Path Table**: Path table collates all path information (for directories) in a more compact form, theoretically allowing for faster navigation. But there are caveats, so by default we don't use this. See ``PathTableRecord`` for details.

* **File/Dir Metadata**: Extra metadata about a file (e.g. long name, permissions, uid/gid etc) might be available in two different fashions:
  1. **External Attributes**: This is a structure designated in ECMA-119 for storing basic metadata information. See ``ExternalAttributeRecord`` for details.
  2. **SUSP**: SUSP (System Use Sharing Protocol), is a specification external to ECMA-119. In this, the ``DirectoryRecord/systemUse`` field of ``DirectoryRecord``s gets repurposed to store the metadata. Each metadata field is stored via a ``SUSPEntry`` record, and a collection of these constitute a ``SUSPArea``.

### Spec Resources
* [ECMA-119 4th edition, June 2019](https://www.ecma-international.org/wp-content/uploads/ECMA-119_4th_edition_june_2019.pdf)
* [SUSP (System Use Sharing Protocol)](https://studylib.net/doc/18849138/ieee-p1281-system-use-sharing-protocol-draft)
* [Rock Ridge](https://web.archive.org/web/20170404043745/http://www.ymi.com/ymi/sites/default/files/pdf/Rockridge.pdf)

## License
ISO9660 is released under the MIT license. See [LICENSE](/amodm/iso9660-swift/blob/main/LICENSE) for details.

## Contribution
Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, shall be licensed as above. You also certify that the contribution was created in whole or part by you, and you have the right to submit the work under the license mentioned above.
