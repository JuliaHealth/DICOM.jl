# DICOM.jl

Julia interface for parsing/writing DICOM (Digital Imaging and Communications in Medicine) files

[![Build Status](https://github.com/JuliaHealth/DICOM.jl/workflows/CI/badge.svg)](https://github.com/JuliaHealth/DICOM.jl/actions)
[![Coverage](https://codecov.io/gh/JuliaHealth/DICOM.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaHealth/DICOM.jl)

## Usage

**Installation**

To install the package:
```
julia> using Pkg
julia> Pkg.add("DICOM")
```

Load the package by
```
julia> using DICOM
```

**Reading Data**

Read a DICOM file by
```
julia> dcm_data = dcm_parse("path/to/dicom/file")
```
The data in `dcm_data` is structured as a dictionary, and individual DICOM elements can be accessed by their hex tag.
For example, the hex tag of "Pixel Data" is `7FE0,0010`, and it can be accessed in Julia by `dcm_data[(0x7FE0,0x0010)]` or by `dcm_data[tag"PixelData"]`.

Multiple DICOM files in a folder can be read by
```
julia> dcm_data_array = dcmdir_parse("path/to/dicom/folder")
```

**Writing Data**

Data can be written to a DICOM file by
```
julia> dcm_write("path/to/output/file", dcm_data)
```

**Additional Notes**

DICOM files should begin with a 128-bytes (which are ignored) followed by the string `DICM`.
If this preamble is missing, then the file can be parsed by `dcm_parse(path/to/file, preamble = false)`.

DICOM files use either explicit or implicit value representation (VR). For implicit files, `DICOM.jl` will use a lookup table to guess the VR from the DICOM element's hex tag. For explicit files, `DICOM.jl` will read the VRs from the file.  

- An auxiliary user-defined dictionary can be supplied to override the default lookup table
    For example, the "Instance Number" - tag `(0x0020,0x0013)` - is an integer (default VR = "IS"). We can read this as a float by setting the VR to "DS" by:
    ```
    my_vrs = Dict( (0x0020,0x0013) => "DS" )
    dcm_data = dcm_parse("path/to/dicom/file", aux_vr = my_vrs)
    ```
    Now `dcm_data[(0x0020,0x0013)]` will return a float instead of an integer.

- It is possible to skip an element by setting its VR to `""`.
    For example, we can skip reading the Instance Number by
    ```
    my_vrs = Dict( (0x0020,0x0013) => "" )
    dcm_data = dcm_parse("path/to/dicom/file", aux_vr = my_vr)
    ```
    and now `dcm_data[(0x0020,0x0013)]` will return an error because the key `(0x0020,0x0013)` doesn't exist - it was skipped during reading.

- The user-supplied VR can contain a master VR with the tag `(0x0000,0x0000)` which will be used whenever `DICOM.jl` is unable to guess the VR on its own. This is convenient for reading older dicom files and skipping retired elements - i.e. where the VR lookup fails - by:
    ```
    my_vrs = Dict( (0x0000,0x0000) => "" )
    dcm_data = dcm_parse("path/to/dicom/file", aux_vr = my_vrs)
    ```

- A user-supplied VR can also be supplied during writing, e.g.:
    ```
    julia> dcm_write("path/to/output/file", dcm_data, aux_vr = user_defined_vr)
    ```
    where `user_defined_vr` is a dictionary which maps the hex tag to the VR.

- A dictionary of VRs can be obtained by passing `return_vr = true` as an argument to `dcm_parse()`, e.g.:
    ```
    julia> (dcm_data, dcm_vr) = dcm_parse("path/to/dicom/file", return_vr = true)
    ```
    and `dcm_vr` will contain a dictionary of VRs for the elements in `dcm_data`
