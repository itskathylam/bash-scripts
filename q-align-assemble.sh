#!/bin/bash

#$ -S /bin/bash                 
#$ -cwd
#$ -j y
#$ -o q-align-assemble.log
#$ -l mem_free=16G 
#$ -l scratch=40G 
#$ -l h_rt=48:00:00 
#$ -t 1-14                      

# Author: Kathy N Lam
# Purpose: Run SGE array job on UCSF wynton cluster to trim NovaSeq reads,
#          align to reference sequence, and de novo assemble aligning reads


#set index from zero for bash arrays
INDEX=$((SGE_TASK_ID-1))


#get samples
FWD=($( cd reads && ls *R1* ))
REV=($( cd reads && ls *R2* ))
FWDFILE="${FWD[$INDEX]}"
REVFILE="${REV[$INDEX]}"
SAMPLE="$( echo "$FWDFILE" | sed -r 's/_S[0-9]{3}.*fastq.gz//' )"


#assign folder paths; make outdirs and clean up old files
LOGS="logs"
FASTP="1-fastp"
BOWTIE="2-bowtie"
SPADES="3-spades"
RESULTS="4-results"

OUTDIRS=($LOGS $FASTP $BOWTIE $SPADES $RESULTS)
for OUTDIR in "${OUTDIRS[@]}"
do
    mkdir -p $OUTDIR
    find $OUTDIR -name $SAMPLE* -exec rm -r {} \; 2>/dev/null
done


#make sample specific logs
exec >> $LOGS/$SAMPLE.log 2>&1


#preamble
echo ""
echo "***********************************************************************************"

echo $(date)
echo $HOSTNAME
echo $JOB_ID
echo $JOB_NAME
echo ""
echo "[ $(date '+%F %H:%M:%S') ] Processing $SAMPLE"


#make temp dir in local /scratch, if it exists, otherwise in /tmp
STARTDIR=$(pwd)

if [[ -z "$TMPDIR" ]]; then
  if [[ -d /scratch ]]; then
    TMPDIR=/scratch/$USER/$SAMPLE; else TMPDIR=/tmp/$USER/$SAMPLE;
  fi
  mkdir -p "$TMPDIR"
  export TMPDIR
fi

echo ""
echo "[ $(date '+%F %H:%M:%S') ] Copying files to local temporary directory..."
echo $TMPDIR

cp reads/$FWDFILE $TMPDIR
cp reads/$REVFILE $TMPDIR
cp -r ref/ $TMPDIR

cd $TMPDIR


#begin
echo ""
echo "[ $(date '+%F %H:%M:%S') ] Trimming reads..."
/turnbaugh/qb3share/shared_resources/sftwrshare/fastp_v0.20.1/fastp \
    --detect_adapter_for_pe \
    --trim_poly_g \
    --html "${SAMPLE}"_fastp_report.html \
    --thread 16 \
    --in1 $FWDFILE \
    --in2 $REVFILE \
    --out1 "${SAMPLE}"_trimmed1.fastq.gz \
    --out2 "${SAMPLE}"_trimmed2.fastq.gz 
  

echo ""
echo "[ $(date '+%F %H:%M:%S') ] Aligning reads using bowtie2..."
/turnbaugh/qb3share/shared_resources/sftwrshare/bowtie2-2.3.5.1-linux-x86_64/bowtie2 \
    -x ref/pBluescriptII_KSminus.fasta \
    --met-file "${SAMPLE}"-bowtie2.log \
    -p 16 \
    --sensitive \
    --no-mixed \
    -q \
    -S $SAMPLE.sam \
    -1 "${SAMPLE}"_trimmed1.fastq.gz \
    -2 "${SAMPLE}"_trimmed2.fastq.gz \
    --no-unal \
    --al-conc-gz "${SAMPLE}"_concordant_%.fastq.gz \
    --un-conc-gz "${SAMPLE}"_discordant_%.fastq.gz

echo ""
echo "[ $(date '+%F %H:%M:%S') ] Assembling reads..."
/turnbaugh/qb3share/shared_resources/sftwrshare/SPAdes-3.13.1-Linux/bin/spades.py \
    -k 21,33,55,77,99,127 \
    --careful \
    --pe1-1 "${SAMPLE}"_concordant_1.fastq.gz \
    --pe1-2 "${SAMPLE}"_concordant_2.fastq.gz \
    --pe2-1 "${SAMPLE}"_discordant_1.fastq.gz \
    --pe2-2 "${SAMPLE}"_discordant_2.fastq.gz \
    -o $SAMPLE

echo ""
echo "[ $(date '+%F %H:%M:%S') ] Copying files from local temporary directory..."
cp "${SAMPLE}"_fastp_report.html $STARTDIR/$FASTP/"${SAMPLE}"_fastp_report.html
cp "${SAMPLE}"-bowtie2.log $STARTDIR/$BOWTIE/"${SAMPLE}"-bowtie2.log
cp -r $SAMPLE $STARTDIR/$SPADES
cp $SAMPLE/scaffolds.fasta $STARTDIR/$RESULTS/$SAMPLE-scaffolds.fasta

echo ""
echo "[ $(date '+%F %H:%M:%S') ] Cleaning up..."
rm "${SAMPLE}"*.gz
rm "${SAMPLE}"_fastp_report.html
rm "${SAMPLE}"-bowtie2.log
rm $SAMPLE.sam
rm -r $SAMPLE
rm -r ref

echo ""
echo "[ $(date '+%F %H:%M:%S') ] Done."
echo ""


#postamble
echo "***********************************************************************************"
echo ""
qstat -j $JOB_ID
