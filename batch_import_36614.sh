#!/usr/bin/env bash
# One-time batch import of all root datasets from project 36614 into the new SUSHI backend.
# Uses the /register endpoint (server-side path, no auth, auto-creates project).

set -uo pipefail

BACKEND="http://localhost:4071"
PROJECT=36614
OK=0
FAIL=0
SKIP=0

register() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "  SKIP (file not found): $path"
        SKIP=$((SKIP + 1))
        return
    fi
    local name
    name=$(basename "$(dirname "$path")")
    local response
    response=$(curl -s -X POST "$BACKEND/projects/$PROJECT/datasets/register" \
        -H "Content-Type: application/json" \
        -d "{\"path\": \"$path\", \"name\": \"$name\"}") || true
    if echo "$response" | grep -q '"data_set_id"'; then
        local id
        id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['data_set_id'])")
        echo "  OK (id=$id): $path"
        OK=$((OK + 1))
    else
        echo "  FAIL: $path"
        echo "        $response"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Batch import into project $PROJECT ==="
echo ""

register /srv/gstore/projects/p36614/iseq420_o35845/dataset.tsv
register /srv/gstore/projects/p36614/iseq428_plate_4444/dataset.tsv
register /srv/gstore/projects/p36614/CUT-TAG-reads-p35864/dataset.tsv
register /srv/gstore/projects/p36614/delme/dataset.tsv
register /srv/gstore/projects/p36614/o36852_NovaSeq_241121_X175_test/dataset.tsv
register /srv/gstore/projects/p36614/o36852_Bowtie2_MS/dataset.tsv
register /srv/gstore/projects/p36614/iSeq440_EM_ctrl/dataset.tsv
register /srv/gstore/projects/p36614/o36852_NovaSeq_241121_X175_SM/dataset.tsv
register /srv/gstore/projects/p36614/iSeq441_EM_ctrl/dataset.tsv
register /srv/gstore/projects/p36614/Iseq442_negCtrl_o36981/dataset.tsv
register /srv/gstore/projects/p36614/iSeq446_20250109_FS10003261_34_BTR67820-1225_Ctrls/dataset.tsv
register /srv/gstore/projects/p36614/cellranger-multi-example-2025-01-29/dataset.tsv
register /srv/gstore/projects/p36614/X198_PhIX/dataset.tsv
register /srv/gstore/projects/p36614/Mi100_20250205_SH00201_0002_ASC2075002-SC3_Ctrls/dataset.tsv
register /srv/gstore/projects/p36614/Mi100_RNASeq_Ctrls/dataset.tsv
register /srv/gstore/projects/p36614/o37286_iSeq_170125_iSeq447/dataset.tsv
register /srv/gstore/projects/p36614/NS2k-453_250205_VH00407_249_AAGFFTGM5_Ctrls/dataset.tsv
register /srv/gstore/projects/p36614/PRJNA647892/dataset.tsv
register /srv/gstore/projects/p36614/BIO435_GSE154927_bulkRNA/dataset.tsv
register /srv/gstore/projects/p36614/o37167_RNABamStats_2025-02-20--09-56-09/dataset.tsv
register /srv/gstore/projects/p36614/20250129_LH00289_0216_B22JMFGLT4_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250221_LH00289_0231_B22K7H3LT4_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250218_LH00289_0228_B22WWNJLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/241220_A01251_0847_AHTVMGDRX3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250214_LH00289_0227_A22VFG2LT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250213_LH00289_0225_B22VCNWLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250207_LH00289_0222_A22VF2GLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/enaTest/dataset.tsv
register /srv/gstore/projects/p36614/o35568_NovaSeq_240807_X112_5M/dataset.tsv
register /srv/gstore/projects/p36614/iSeq456_20250317_FS10003261_40_BWB90516-2320_Ctrls/dataset.tsv
register /srv/gstore/projects/p36614/p35006_o37938/dataset.tsv
register /srv/gstore/projects/p36614/Mi100_20250409_SH00201_0011_ASC2080548-SC3_Ctrls/dataset.tsv
register /srv/gstore/projects/p36614/test_LO/dataset.tsv
register /srv/gstore/projects/p36614/single_cell_example_raw/dataset.tsv
register /srv/gstore/projects/p36614/20250320_LH00289_0245_A22VF2NLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250404_LH00289_0255_B22VCTLLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250408_LH00289_0256_A22V5KLLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250417_LH00289_0262_A22VCNYLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250417_LH00289_0263_B22TLJVLT4_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250423_LH00289_0264_A22VCTCLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250425_LH00289_0267_B22VFLVLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250430_LH00289_0268_A22VF2JLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/20250502_LH00289_0269_A22VCTFLT3_PhiX/dataset.tsv
register /srv/gstore/projects/p36614/PhIX_NovaSeqX_02_03_04_2025/dataset.tsv
register /srv/gstore/projects/p36614/X270_L5_6_7_controls/dataset.tsv
register /srv/gstore/projects/p36614/o38437_EMSeqCtrl_Mi100_016QC/dataset.tsv
register /srv/gstore/projects/p36614/o38437_pooledSamples_Mi100_016QC/dataset.tsv
register /srv/gstore/projects/p36614/o38749_o38697_Aviti_250530_AV098/dataset.tsv
register /srv/gstore/projects/p36614/X270_p2220_HB129_EMSeq_v2_Trial/dataset.tsv
register /srv/gstore/projects/p36614/o000000_MiSeq-i100_250617_Mi100_019QC/dataset.tsv
register /srv/gstore/projects/p36614/o000000_MiSeq-i100_250618_Mi100_020/dataset.tsv
register /srv/gstore/projects/p36614/10X_scRNASeq_o5495_o5444/dataset.tsv
register /srv/gstore/projects/p36614/withoutIndexRead/dataset.tsv
register /srv/gstore/projects/p36614/10X_scRNASeq_o5495_o5444_subsample_tar/dataset.tsv
register /srv/gstore/projects/p36614/10X_scRNASeq_o5495_o5444_subsample_untar/dataset.tsv
register /srv/gstore/projects/p36614/ENA_test/dataset.tsv
register /srv/gstore/projects/p36614/ENA_App_PRJEB31934/dataset.tsv
register /srv/gstore/projects/p36614/BIO435_GSE154927_bulkRNA_subsampled/dataset.tsv
register /srv/gstore/projects/p36614/o38990_NovaSeq_250730_X319/dataset.tsv
register /srv/gstore/projects/p36614/o39241_MiSeq-i100_test/dataset.tsv
register /srv/gstore/projects/p36614/o29104_testSet_smRNA/dataset.tsv
register /srv/gstore/projects/p36614/o37699_Kallisto_Spleen_combinedFactor/dataset.tsv
register /srv/gstore/projects/p36614/10x_flex_sampleData/dataset.tsv
register /srv/gstore/projects/p36614/o40245_rawData/dataset.tsv
register /srv/gstore/projects/p36614/o39541_PeakCounts/dataset.tsv
register /srv/gstore/projects/p36614/o40214_X395/dataset.tsv
register /srv/gstore/projects/p36614/o40449_rawReads/dataset.tsv
register /srv/gstore/projects/p36614/BSSeq_PRJNA208011/dataset.tsv
register /srv/gstore/projects/p36614/EM_Seq_PRJNA789458/dataset.tsv
register /srv/gstore/projects/p36614/STAR_2026-03-09--14-00-43/dataset.tsv
register /srv/gstore/projects/p36614/BIO675_o5495_o5444_CellRangerCount_2024-03-18--11-52-08/dataset.tsv
register /srv/gstore/projects/p36614/BIO393_o6381_NextSeq500_20191112_NS347/dataset.tsv
register /srv/gstore/projects/p36614/o41794/dataset.tsv

echo ""
echo "=== Done: $OK imported, $FAIL failed, $SKIP skipped (file not found) ==="
