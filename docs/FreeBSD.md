# Swift on FreeBSD

This document outlines the steps involved in building and using Swift on the
[FreeBSD operating system](https://www.freebsd.org).

## Prerequisites

Swift requires a base system of FreeBSD
[13.1-RELEASE](https://www.freebsd.org/releases/13.1R/)
or newer.[^why-13.1]

[^why-13.1]: FreeBSD 13.1-RELEASE contains two fixes required to build Swift.
First, it
[comes with](https://github.com/freebsd/freebsd-src/commit/349cc55c9796c4596a5b9904cd3281af295f878f)
a toolchain based on LLVM 15, which means that its `lld` supports
`-start-stop-gc`.  Second, it
[uses](https://github.com/freebsd/freebsd-src/commit/c00d345665366a89aaba7244d6f078dc756f4c53)
the `unwind.h` from LLVM's
libunwind, not the one from `libcxxrt`, which requires `_GNU_SOURCE` to be
defined in order to call `_Unwind_Backtrace`.  See
[this PR](https://github.com/apple/swift/pull/61693).

The following ports are required for building.  You can build them manually from
the ports tree or simply install them with `pkg install`.

- bash
- cmake
- e2fsprogs-libuuid
- git
- ninja
- python3

These packages are required only for building; they are _not_ required for
running an already-built version of Swift.

## libc++ modifications

The libc++ headers in FreeBSD 13.1-RELEASE require slight modifications in order
to build Swift.

1. The implementation of `std::pair` must be modified such that its copy
constructor is trivial (as the C++ standard requires).  For historical reasons,
this is not currently the case in FreeBSD 13.1 (though there is
[ongoing work](https://reviews.llvm.org/D126462) to fix it for FreeBSD 14.0).

2. The libc++ `module.modulemap` requires a small tweak to fix the
`std.depr.stdint_h` module.  See
[this bug report](https://github.com/llvm/llvm-project/issues/58781) for
details.

Both changes can be applied using the following patch:

```patch
--- __config
+++ __config
@@ -127,7 +127,7 @@
 #  endif
 // Feature macros for disabling pre ABI v1 features. All of these options
 // are deprecated.
-#  if defined(__FreeBSD__)
+#  if defined(__FreeBSD__) && (0)
 #    define _LIBCPP_DEPRECATED_ABI_DISABLE_PAIR_TRIVIAL_COPY_CTOR
 #  endif
 #endif

--- module.modulemap
+++ module.modulemap
@@ -29,6 +29,13 @@
       export *
     }
     // <float.h> provided by compiler or C library.
+    module stdint_h {
+      header "stdint.h"
+      export *
+      // FIXME: This module only exists on OS X and for some reason the
+      // wildcard above doesn't export it.
+      export Darwin.C.stdint
+    }
     module inttypes_h {
       header "inttypes.h"
       export stdint_h
@@ -55,13 +62,6 @@
     module stddef_h {
       // <stddef.h>'s __need_* macros require textual inclusion.
       textual header "stddef.h"
-    }
-    module stdint_h {
-      header "stdint.h"
-      export *
-      // FIXME: This module only exists on OS X and for some reason the
-      // wildcard above doesn't export it.
-      export Darwin.C.stdint
     }
     module stdio_h {
       // <stdio.h>'s __need_* macros require textual inclusion.
```

Apply the patch with:

```shell
# patch -p0 -i <path to patch> -d /usr/include/c++/v1
```

If you wish, you can reverse-apply the patch later by running the same `patch`
command with `-R`.

## Downloading the source

Next, create your build workspace by checking out the source repositories.

The commands below specify `--depth=1` to avoid downloading the entire (large)
repository histories; omit that argument if you prefer to keep the histories.

### Top of tree

Note that you'll need to replace `<llvm stabilization branch>` with the current
stabilization branch; at time of writing, it is `stable/20220421`.  To find the
name of the current stabilization branch, look in
[`update-checkout-config.json`](https://github.com/apple/swift/blob/main/utils/update_checkout/update-checkout-config.json).
Use the value of `branch-schemes/main/repos/llvm-project`.

```shell
$ mkdir swift && cd swift
$ git clone -b main --depth=1 https://github.com/apple/swift
$ git clone -b <llvm stabilization branch> --depth=1 https://github.com/apple/llvm-project
$ git clone -b gfm --depth=1 https://github.com/apple/swift-cmark cmark
$ git clone -b main --depth=1 https://github.com/apple/swift-syntax
$ git clone -b main --depth=1 https://github.com/apple/swift-experimental-string-processing.git
```

### Swift releases newer than Swift 5.7.x

To build a released version of Swift, check out the branches corresponding to
the release.  For example, for Swift 5.8, check out the following:

```shell
$ mkdir swift && cd swift
$ git clone -b release/5.8 --depth=1 https://github.com/apple/swift
$ git clone -b swift/release/5.8 --depth=1 https://github.com/apple/llvm-project
$ git clone -b release/5.8 --depth=1 https://github.com/apple/swift-cmark cmark
$ git clone -b release/5.8 --depth=1 https://github.com/apple/swift-syntax
$ git clone -b swift/release/5.8 --depth=1 https://github.com/apple/swift-experimental-string-processing.git
```

### Swift 5.7

For Swift 5.7, follow the directions in "Swift releases newer than Swift 5.7.x",
except that, for the `swift` repository, use the following alternate repository
and branch:

```shell
$ git clone -b freebsd-swift-5.7-RELEASE --depth=1 https://github.com/mhjacobson/swift
```

The Swift 5.7 sources in the official Apple repository are missing some fixes
required for FreeBSD.  The alternate repository and branch above contain those
fixes.

The fixes have been upstreamed and should appear in official Swift releases
starting with Swift 5.8.

### Alternatively: using `update-checkout`

Alternatively, you can use the `update-checkout` script in the `utils` directory
of the Swift repository to check out the correct branches of the other
repositories.

## Configuring the build

In your build workspace, write the following to a shell script named
`configure.sh`:

```shell
#!/bin/sh

SRCROOT="`pwd`/.."

cmake \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/usr/local \
	-DLLVM_ENABLE_PROJECTS=clang \
	-DLLVM_TARGETS_TO_BUILD=X86 \
	-DLLVM_EXTERNAL_PROJECTS="cmark;swift" \
	-DLLVM_EXTERNAL_CMARK_SOURCE_DIR="${SRCROOT}/cmark" \
	-DLLVM_EXTERNAL_SWIFT_SOURCE_DIR="${SRCROOT}/swift" \
	-DSWIFT_PATH_TO_SWIFT_SYNTAX_SOURCE="${SRCROOT}/swift-syntax" \
	-DSWIFT_ENABLE_DISPATCH=OFF \
	-DSWIFT_IMPLICIT_CONCURRENCY_IMPORT=OFF \
	-DSWIFT_USE_LINKER=ld \
	-DSWIFT_BUILD_STATIC_STDLIB=ON \
	-DBOOTSTRAPPING_MODE=BOOTSTRAPPING \
	-DSWIFT_ENABLE_EXPERIMENTAL_STRING_PROCESSING=ON \
	-DEXPERIMENTAL_STRING_PROCESSING_SOURCE_DIR="${SRCROOT}/swift-experimental-string-processing" \
	-G Ninja \
	../llvm-project/llvm
```

Then configure a build directory:

```shell
$ mkdir build && cd build
$ ../configure.sh
```

### Alternatively: configuring with `build-script`

TK

## Building

To build, simply run `ninja` in the build directory.  At time of writing, there
are nearly 5,000 build steps involved in a clean build, so it might take a
while.

### Rebuilding

To rebuild after making a source change, in most cases it will suffice simply to
`cd` back to your build directory and run `ninja`.

If your change involved changing the build system, it's a good idea to try a
clean build by removing the `build` directory and re-configuring.

## Installing

Install a root of the Swift compiler and standard library:

```shell
$ env DESTDIR=/tmp/install ninja install-compiler install-autolink-driver install-stdlib install-sdk-overlay
```

Alternatively, install a root of all Swift components:

```shell
$ env DESTDIR=/tmp/install ninja install-swift-components
```
