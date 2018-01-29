using Base.Test
using DICOM

testdir = joinpath(Pkg.dir("DICOM"),"test","testdata")

if !isdir(testdir)
    mkdir(testdir)
end

# TEST SET 1: Simple Reading/Writing

fileMR = joinpath(testdir, "MR_Implicit_Little")
fileCT = joinpath(testdir, "CT_Explicit_Little")
fileMG = joinpath(testdir, "MG_Explicit_Little.zip")

# Don't download files if they already exist
if !isfile(fileMR) && !isfile(fileMR) && !isfile(fileMR)
    download("http://www.barre.nom.fr/medical/samples/files/MR-MONO2-16-head.gz", fileMR*".gz")
    download("http://www.barre.nom.fr/medical/samples/files/CT-MONO2-16-brain.gz", fileCT*".gz")
    download("http://www.dclunie.com/images/pixelspacingtestimages.zip", fileMG)

    run(`gunzip -f $(fileMR*".gz")`)
    run(`gunzip -f $(fileCT*".gz")`)
    run(`unzip -o $fileMG -d $testdir`)
end

# Load dicom data
dcmMR_partial = dcm_parse(fileMR, maxGrp=0x0008)
dcmMR = dcm_parse(fileMR)
dcmCT = dcm_parse(fileCT)
(dcmMG, vrMG) = dcm_parse(joinpath(testdir, "DISCIMG/IMAGES/MGIMAGEA"), true)

@testset "Loading DICOM data" begin
    @test dcmMR_partial[(0x0008,0x0060)] == "MR"
    @test haskey(dcmMR_partial, (0x7FE0,0x0010)) == false
   
    @test dcmMR[(0x0008,0x0060)] == "MR"
    @test dcmCT[(0x0008,0x0060)] == "CT"
    @test dcmMG[(0x0008,0x0060)] == "MG"

    @test length(dcmMR[(0x7FE0,0x0010)]) == 65536
    @test length(dcmCT[(0x7FE0,0x0010)]) == 262144
    @test length(dcmMG[(0x7FE0,0x0010)]) == 262144

    # Test lookup-by-fieldname
    @test dcmMR[(0x0008,0x0060)] == lookup(dcmMR, "Modality")
    @test dcmMR[(0x7FE0,0x0010)] == lookup(dcmMR, "Pixel Data")
end

# Define two output files for each dcm - data will be saved, reloaded, then saved again
outMR1 = joinpath(testdir,"outMR1.dcm")
outMR2 = joinpath(testdir,"outMR2.dcm")

outCT1 = joinpath(testdir,"outCT1.dcm")
outCT2 = joinpath(testdir,"outCT2.dcm")

outMG1 = joinpath(testdir,"outMG1.dcm")
outMG1b = joinpath(testdir,"outMG1b.dcm")
outMG2 = joinpath(testdir,"outMG2.dcm")

@testset "Writing DICOM data" begin
    # No specific test, just test if file is saved without errors
    outIO = open(outMR1, "w+"); dcm_write(outIO,dcmMR); close(outIO)
    outIO = open(outCT1, "w+"); dcm_write(outIO,dcmCT); close(outIO)
    outIO = open(outMG1, "w+"); dcm_write(outIO,dcmMG,vrMG); close(outIO)
    dcm_write(outMG1b,dcmMG,vrMG)
end

# Load saved DICOM data
dcmMR1 = dcm_parse(outMR1)
dcmCT1 = dcm_parse(outCT1)
(dcmMG1, vrMG1) = dcm_parse(outMG1, true)

@testset "Consistence of Reading/Writing data" begin
    # Confirm that re-loading/saving leads to same file
    outIO = open(outMR2, "w+"); dcm_write(outIO,dcmMR1); close(outIO)
    outIO = open(outCT2, "w+"); dcm_write(outIO,dcmCT1); close(outIO)
    outIO = open(outMG2, "w+"); dcm_write(outIO,dcmMG1, vrMG1); close(outIO)

    @test read(outMR1)==read(outMR2)
    @test read(outCT1)==read(outCT2)
    @test read(outMG1)==read(outMG2)

    # Repeat first tests on reloaded data
    @test dcmMR1[(0x0008,0x0060)] == "MR"
    @test dcmCT1[(0x0008,0x0060)] == "CT"
    @test dcmMG1[(0x0008,0x0060)] == "MG"

    @test length(dcmMR1[(0x7FE0,0x0010)]) == 65536
    @test length(dcmCT1[(0x7FE0,0x0010)]) == 262144
    @test length(dcmMG1[(0x7FE0,0x0010)]) == 262144

    # Test lookup-by-fieldname; cross-compare dcmMR with dcmMR1
    @test dcmMR1[(0x0008,0x0060)] == lookup(dcmMR, "Modality")
    @test dcmMR1[(0x7FE0,0x0010)] == lookup(dcmMR, "Pixel Data")
end

# TEST SET 2: Reading uncommon datasets

# 1. Loading DICOM file with missing header
fileOT = joinpath(testdir, "OT_Implicit_Little_Headless")
download("http://www.barre.nom.fr/medical/samples/files/OT-MONO2-8-a7.gz", fileOT*".gz")
run(`gunzip -f $(fileOT*".gz")`)

dcmOT = dcm_parse(fileOT, header=false)

# 2. Loading DICOM file with missing header and retired DICOM elements
fileCT = joinpath(testdir, "CT-Implicit_Little_Headless_Retired")
download("http://www.barre.nom.fr/medical/samples/files/CT-MONO2-12-lomb-an2.gz", fileCT*".gz")
run(`gunzip -f $(fileCT*".gz")`)

# 2a. With user-supplied VRs
dVR_CTa = Dict( 
    (0x0008,0x0010) => "SH",
    (0x0008,0x0040) => "US",
    (0x0008,0x0041) => "LO",
    (0x0018,0x1170) => "DS",
    (0x0020,0x0030) => "DS",
    (0x0020,0x0035) => "DS",
    (0x0020,0x0050) => "DS",
    (0x0020,0x0070) => "LO",
    (0x0028,0x0005) => "US",
    (0x0028,0x0040) => "CS",
    (0x0028,0x0200) => "US")
dcmCTa = dcm_parse(fileCT, header=false, dVR=dVR_CTa);

# 2b. With a master VR which skips elements
# Here we skip any element where lookup_vr() fails
# And we also force (0x0018,0x1170) to be read as float instead of integer
dVR_CTb = Dict( (0x0000,0x0000) => "",  (0x0018,0x1170) => "DS")
dcmCTb = dcm_parse(fileCT, header=false, dVR=dVR_CTb);

# 3. Loading DICOM file containing multiple frames

fileMR_multiframe = joinpath(testdir, "MR-Explicit_Little_MultiFrame")
dlFile = "MR-heart.gz"
download("http://www.barre.nom.fr/medical/samples/files/MR-MONO2-8-16x-heart.gz", fileMR_multiframe*".gz")
run(`gunzip -f $(fileMR_multiframe*".gz")`)

dcmMR_multiframe = dcm_parse(fileMR_multiframe)

@testset "Loading uncommon DICOM data" begin
    @test dcmOT[(0x0008,0x0060)] == "OT"
    
    @test dcmCTa[(0x0008,0x0060)] == "CT"
    @test dcmCTb[(0x0008,0x0060)] == "CT"
    @test haskey(dcmCTa, (0x0028,0x0040)) # dcmCTa should contain retired element
    @test !haskey(dcmCTb, (0x0028,0x0040)) # dcmCTb skips retired elements

    @test dcmMR_multiframe[(0x0008,0x0060)] == "MR"
end