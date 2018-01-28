using Base.Test
using DICOM

testdir = joinpath(Pkg.dir("DICOM"),"test","testdata")

if !isdir(testdir)
    mkdir(testdir)
end

fileMR = joinpath(testdir, "MR_Implicit_Little")
fileCT = joinpath(testdir, "CT_Explicit_Little")
fileMG = joinpath(testdir, "MG_Explicit_Little.zip")

# Don't download files if they already exist
if !isfile(fileMR) && !isfile(fileMR) && !isfile(fileMR)
    download("http://www.barre.nom.fr/medical/samples/files/MR-MONO2-16-head.gz", fileMR*".gz")
    download("http://www.barre.nom.fr/medical/samples/files/CT-MONO2-16-ankle.gz", fileCT*".gz")
    download("http://www.dclunie.com/images/pixelspacingtestimages.zip", fileMG)

    run(`gunzip -f $(fileMR*".gz")`)
    run(`gunzip -f $(fileCT*".gz")`)
    run(`unzip -o $fileMG -d $testdir`)
end

# Load dicom data
dcmMR = dcm_parse(fileMR)
dcmCT = dcm_parse(fileCT)
(dcmMG, vrMG) = dcm_parse(joinpath(testdir, "DISCIMG/IMAGES/MGIMAGEA"), true)

@testset "Loading DICOM data" begin
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
