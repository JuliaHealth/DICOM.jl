# DICOM.jl

Julia interface for parsing/writing DICOM files

[![Build Status](https://travis-ci.org/JuliaIO/DICOM.jl.svg?branch=master)](https://travis-ci.org/JuliaIO/DICOM.jl)
[![Code Coverage](https://codecov.io/gh/JuliaIO/DICOM.jl/branch/master/graphs/badge.svg?)](https://codecov.io/gh/JuliaIO/DICOM.jl/branch/master)

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
julia> dcmData = dcm_parse("path/to/dicom/file")
```
The data in `dcmData` is structured as a dictionary, and individual DICOM elements can be accessed by their hex tag. 
For example, the hex tag of "Pixel Data" is `7FE0,0010`, and it can be accessed in Julia by `dcmData[(0x7FE0,0x0010)]` or by `dcmData[tag"Pixel Data"]`. 

**Writing Data**

Data can be written to a DICOM file by
```
julia> dcm_write("path/to/output/file", dcmData)
```

**Additional Notes**

DICOM files use either explicit or implicit value representation (VR). For implicit files, `DICOM.jl` will use a lookup table to guess the VR from the DICOM element's hex tag. For explicit files, `DICOM.jl` will read the VRs from the file.  

- A user-defined dictionary can be supplied to override the default lookup table
    For example, the "Instance Number" - tag `(0x0020,0x0013)` - is an integer (default VR = "IS"). We can read this as a float by setting the VR to "DS" by:
    ```
    myVR = Dict( (0x0020,0x0013) => "DS" )
    dcmData = dcm_parse("path/to/dicom/file", dVR = myVR)
    ```
    Now `dcmData[(0x0020,0x0013)]` will return a float instead of an integer.

- It is possible to skip an element by setting its VR to `""`. 
    For example, we can skip reading the Instance Number by
    ```
    myVR = Dict( (0x0020,0x0013) => "" )
    dcmData = dcm_parse("path/to/dicom/file", dVR = myVR)
    ```
    and now `dcmData[(0x0020,0x0013)]` will return an error because the key `(0x0020,0x0013)` doesn't exist - it was skipped during reading.

- The user-supplied VR can contain a master VR with the tag `(0x0000,0x0000)` which will be used whenever `DICOM.jl` is unable to guess the VR on its own. This is convenient for reading older dicom files and skipping retired elements - i.e. where the VR lookup fails - by:
    ```
    myVR = Dict( (0x0000,0x0000) => "" )
    dcmData = dcm_parse("path/to/dicom/file", dVR = myVR)
    ```

- A user-supplied VR can also be supplied during writing, e.g.:
    ```
    # Note that dcm_write doesn't use a named input, unlike dcm_parse with "dVR ="
    julia> dcm_write("path/to/output/file", dcmData, dcmVR)
    ```
    where `dcmVR` is a dictionary which maps the hex tag to the VR.

- A dictionary of VRs can be obtained by passing `true` as a 2nd argument to `dcm_parse()`, e.g.:
    ```
    julia> (dcmData, dcmVR) = dcm_parse("path/to/dicom/file", true)
    ```
    and `dcmVR` will contain a dictionary of VRs for all of the elements in `dcmData`

