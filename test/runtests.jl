using Test
using DICOM

const data_folder = joinpath(@__DIR__, "testdata")
if !isdir(data_folder)
    mkdir(data_folder)
end

const dicom_samples = Dict(
    "CT_Explicit_Little.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/CT_Explicit_Little.dcm",
    "CT_JPEG70.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/CT_JPEG70.dcm",
    "CT_Implicit_Little_Headless_Retired.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/CT_Implicit_Little_Headless_Retired.dcm",
    "MG_Explicit_Little.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/MG_Explicit_Little.dcm",
    "MR_Explicit_Little_MultiFrame.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/MR_Explicit_Little_MultiFrame.dcm",
    "MR_Implicit_Little.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/MR_Implicit_Little.dcm",
    "MR_UnspecifiedLength.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/MR_UnspecifiedLength.dcm",
    "OT_Implicit_Little_Headless.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/OT_Implicit_Little_Headless.dcm",
    "US_Explicit_Big_RGB.dcm" =>
        "https://github.com/notZaki/DICOMSamples/raw/master/DICOMSamples/US_Explicit_Big_RGB.dcm",
    "DX_Implicit_Little_Interleaved.dcm" =>
        "https://github.com/OHIF/viewer-testdata/raw/master/dcm/zoo-exotic/5.dcm",
)

function download_dicom(filename; folder = data_folder)
    @assert haskey(dicom_samples, filename)
    url = dicom_samples[filename]
    filepath = joinpath(folder, filename)
    if !isfile(filepath)
        download(url, filepath)
    end
    return filepath
end

@testset "Download Test Data" begin
    for filename in keys(dicom_samples)
        download_dicom(filename)
    end
end

@testset "Reading DICOM" begin
    fileMR = download_dicom("MR_Implicit_Little.dcm")
    fileCT = download_dicom("CT_Explicit_Little.dcm")
    fileMG = download_dicom("MG_Explicit_Little.dcm")

    dcmMR_partial = dcm_parse(fileMR, max_group = 0x0008)
    dcmMR = dcm_parse(fileMR)
    dcmCT = dcm_parse(fileCT)
    dcmMG = dcm_parse(fileMG)

    @test dcmMR_partial[(0x0008, 0x0060)] == "MR"
    @test haskey(dcmMR_partial, (0x7FE0, 0x0010)) == false

    @test dcmMR[(0x0008, 0x0060)] == "MR"
    @test dcmCT[(0x0008, 0x0060)] == "CT"
    @test dcmMG[(0x0008, 0x0060)] == "MG"

    @test length(dcmMR[(0x7FE0, 0x0010)]) == 65536
    @test length(dcmCT[(0x7FE0, 0x0010)]) == 262144
    @test length(dcmMG[(0x7FE0, 0x0010)]) == 262144

    # Test lookup-by-fieldname
    @test dcmMR[(0x0008, 0x0060)] == lookup(dcmMR, "Modality")
    @test dcmMR[(0x7FE0, 0x0010)] == lookup(dcmMR, "Pixel Data")

    # test reading of SQ
    @test isa(dcmMG.AnatomicRegionSequence, Vector{DICOM.DICOMData})
end

@testset "Writing DICOM" begin
    fileMR = download_dicom("MR_Implicit_Little.dcm")
    fileCT = download_dicom("CT_Explicit_Little.dcm")
    fileMG = download_dicom("MG_Explicit_Little.dcm")

    dcmMR = dcm_parse(fileMR)
    dcmCT = dcm_parse(fileCT)
    dcmMG = dcm_parse(fileMG)

    # Define two output files for each dcm - data will be saved, reloaded, then saved again
    outMR1 = joinpath(data_folder, "outMR1.dcm")
    outMR2 = joinpath(data_folder, "outMR2.dcm")
    outCT1 = joinpath(data_folder, "outCT1.dcm")
    outCT2 = joinpath(data_folder, "outCT2.dcm")
    outMG1 = joinpath(data_folder, "outMG1.dcm")
    outMG1b = joinpath(data_folder, "outMG1b.dcm")
    outMG2 = joinpath(data_folder, "outMG2.dcm")

    # Write DICOM files
    dcm_write(outMR1, dcmMR)
    dcm_write(outCT1, dcmCT)
    dcm_write(outMG1, dcmMG; aux_vr = dcmMG.vr)
    open(outMG1b, "w") do io
        dcm_write(io, dcmMG; aux_vr = dcmMG.vr)
    end
    # Reading DICOM files which were written from previous step
    dcmMR1 = dcm_parse(outMR1)
    dcmCT1 = dcm_parse(outCT1)
    dcmMG1 = dcm_parse(outMG1)
    # Write DICOM files which were re-read from previous step
    dcm_write(outMR2, dcmMR1)
    dcm_write(outCT2, dcmCT1)
    dcm_write(outMG2, dcmMG1; aux_vr = dcmMG1.vr)

    # Test consistency of written files after the write-read-write cycle
    @test read(outMR1) == read(outMR2)
    @test read(outCT1) == read(outCT2)
    @test read(outMG1) == read(outMG2)

    # Repeat first testset on written data
    @test dcmMR1[(0x0008, 0x0060)] == "MR"
    @test dcmCT1[(0x0008, 0x0060)] == "CT"
    @test dcmMG1[(0x0008, 0x0060)] == "MG"

    @test length(dcmMR1[(0x7FE0, 0x0010)]) == 65536
    @test length(dcmCT1[(0x7FE0, 0x0010)]) == 262144
    @test length(dcmMG1[(0x7FE0, 0x0010)]) == 262144

    # Test lookup-by-fieldname; cross-compare dcmMR with dcmMR1
    @test dcmMR1[(0x0008, 0x0060)] == lookup(dcmMR, "Modality")
    @test dcmMR1[(0x7FE0, 0x0010)] == lookup(dcmMR, "Pixel Data")
end

@testset "Uncommon DICOM" begin
    # 1. DICOM file with missing preamble
    fileOT = download_dicom("OT_Implicit_Little_Headless.dcm")
    dcmOT = dcm_parse(fileOT, preamble = false)
    @test dcmOT[(0x0008, 0x0060)] == "OT"

    # 2. DICOM file with missing preamble and retired DICOM elements
    fileCT = download_dicom("CT_Implicit_Little_Headless_Retired.dcm")
    # 2a. Read with user-supplied VRs
    dVR_CTa = Dict(
        (0x0008, 0x0010) => "SH",
        (0x0008, 0x0040) => "US",
        (0x0008, 0x0041) => "LO",
        (0x0018, 0x1170) => "DS",
        (0x0020, 0x0030) => "DS",
        (0x0020, 0x0035) => "DS",
        (0x0020, 0x0050) => "DS",
        (0x0020, 0x0070) => "LO",
        (0x0028, 0x0005) => "US",
        (0x0028, 0x0040) => "CS",
        (0x0028, 0x0200) => "US",
    )
    dcmCTa = dcm_parse(fileCT, preamble = false, aux_vr = dVR_CTa)
    # 2b. Read with a master VR which skips elements
    # Here we skip the element (0x0028, 0x0040)
    # and we also force (0x0018,0x1170) to be read as float instead of integer
    dVR_CTb = Dict((0x0028, 0x0040) => "", (0x0018, 0x1170) => "DS")
    dcmCTb = dcm_parse(fileCT, preamble = false, aux_vr = dVR_CTb)
    @test dcmCTa[(0x0008, 0x0060)] == "CT"
    @test dcmCTb[(0x0008, 0x0060)] == "CT"
    @test haskey(dcmCTa, (0x0028, 0x0040)) # dcmCTa should contain retired element
    @test !haskey(dcmCTb, (0x0028, 0x0040)) # dcmCTb skips retired elements

    rescale!(dcmCTa)
    @test minimum(dcmCTa[(0x7fe0, 0x0010)]) == -949
    @test maximum(dcmCTa[(0x7fe0, 0x0010)]) == 1132
    rescale!(dcmCTa, :backward)
    @test minimum(dcmCTa[(0x7fe0, 0x0010)]) == minimum(dcmCTb[(0x7fe0, 0x0010)])
    @test maximum(dcmCTa[(0x7fe0, 0x0010)]) == maximum(dcmCTb[(0x7fe0, 0x0010)])

    # 3. DICOM file containing multiple frames
    fileMR_multiframe = download_dicom("MR_Explicit_Little_MultiFrame.dcm")
    dcmMR_multiframe = dcm_parse(fileMR_multiframe)
    @test dcmMR_multiframe[(0x0008, 0x0060)] == "MR"

    # 4. DICOM with unspecified_length()
    fileMR_UnspecifiedLength = download_dicom("MR_UnspecifiedLength.dcm")
    dcmMR_UnspecifiedLength = dcm_parse(fileMR_UnspecifiedLength)
    @test size(dcmMR_UnspecifiedLength[tag"Pixel Data"]) === (256, 256, 27)
end

@testset "Test big endian" begin
    fileUS = download_dicom("US_Explicit_Big_RGB.dcm")
    dcmUS = dcm_parse(fileUS)
    @test Int(dcmUS[(0x7fe0, 0x0000)]) == 921612
    @test size(dcmUS[(0x7fe0, 0x0010)]) == (480, 640, 3)
end

@testset "Test interleaved" begin
    fileDX = download_dicom("DX_Implicit_Little_Interleaved.dcm")
    dcmDX = dcm_parse(fileDX)
    @test size(dcmDX[(0x7fe0, 0x0010)]) == (1590, 2593, 3)
end

@testset "Test Compressed" begin
    fileCT = download_dicom("CT_JPEG70.dcm")
    dcm_parse(fileCT)
end

@testset "DICOMData API" begin
    dcmFile = download_dicom("MR_Implicit_Little.dcm")
    dcm = dcm_parse(dcmFile)
    @test length(keys(dcm)) == 87
    @test haskey(dcm, "PatientName")
    @test haskey(dcm, :PatientName)
    @test haskey(dcm, (0x0010, 0x0010))
    @test dcm.PatientName ===
          dcm[:PatientName] ===
          dcm["PatientName"] ===
          dcm[(0x0010, 0x0010)] ===
          "Anonymized"
    dcm.PatientName = "Tom"
    @test dcm.PatientName == "Tom"
    dcm[:PatientName] = "Dick"
    @test dcm.PatientName == "Dick"
    dcm["PatientName"] = "Harry"
    @test dcm.PatientName == "Harry"
    dcm[(0x0010, 0x0010)] = "Anonymized"
    @test dcm.PatientName ===
          dcm[:PatientName] ===
          dcm["PatientName"] ===
          dcm[(0x0010, 0x0010)] ===
          "Anonymized"
    @test length(propertynames(dcm)) == 85
end

@testset "Parse entire folder" begin
    # Following files have missing preamble and won't be parsed
    # ["OT_Implicit_Little_Headless.dcm", "CT_Implicit_Little_Headless_Retired.dcm"]
    dcms = dcmdir_parse(data_folder)
    @test issorted([dcm[tag"Instance Number"] for dcm in dcms])
    @test length(dcms) == length(readdir(data_folder)) - 2 # -2 because of note above
end

@testset "Test tag macro" begin
    @test tag"Modality" === (0x0008, 0x0060) === DICOM.fieldname_dict[:Modality]
    @test tag"Shutter Overlay Group" ===
          (0x0018, 0x1623) ===
          DICOM.fieldname_dict[:ShutterOverlayGroup]
    @test tag"Histogram Last Bin Value" === (0x0060, 0x3006)
    DICOM.fieldname_dict[:HistogramLastBinValue]

    # test that compile time error is thrown if tag does not exist
    @test macroexpand(Main, :(tag"Modality")) === (0x0008, 0x0060)
    @test_throws LoadError macroexpand(Main, :(tag"nonsense"))
end
