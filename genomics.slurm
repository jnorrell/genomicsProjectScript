#!/bin/bash

## A general genomics workflow for Bioinformatics for Research

#SBATCH -J genomics	# Job name
#SBATCH -o genomics.%j.out	# Name of stdout output file (%j expands to jobId)
#SBATCH -p normal	# Queue name
#SBATCH -n 16	# Total number of  tasks requested
#SBATCH -t 2:00:00	# Run time (hh:mm:ss) 
#SBATCH --mail-user jnorrell2@patriots.uttyler.edu	# email to notify	
#SBATCH --mail-type END	# when to notify email
#SBATCH -A UT-Tyler-Bioinformat	# Allocation name to charge job against

## USAGE: sbatch genomics.slurm
## DEPENDENCIES: 
#	already installed in Stampede: 
#		fastqc: quality assessment, http://www.bioinformatics.babraham.ac.uk/projects/fastqc/
#		velvet: genome assembler, https://www.ebi.ac.uk/~zerbino/velvet/
#		bwa: read mapping, http://bio-bwa.sourceforge.net
#		samtools: ngs manipulation, http://www.htslib.org
#		blast: sequence similarity searching, http://www.ncbi.nlm.nih.gov/news/04-05-2013-blast-2-2-28/
#	in $WORK/myapps
#		prinseq: sequence read trimming/filtering, http://prinseq.sourceforge.net
#		bcfutils and vcfutils.pl: variant call analysis, https://samtools.github.io/bcftools/bcftools.html
# jnorrell.fastq, referenceProject.fa, and genesProject.fa in genomics/data

# load modules pre-installed in Stampede
module load fastqc velvet bwa samtools blast

# move to project directory and data folder
cd $WORK/genomicsProject/data

# assess raw data for quality
fastqc jnorrell.fastq

#trim and filter raw data
perl $WORK/myapps/prinseq-lite-0.20.4/prinseq-lite.pl -fastq jnorrell.fastq -trim_left 4 min_qual_mean 20 -ns_max_n 3 -out_good jnorrellTrim

# reassess trimmed data for quality
fastqc jnorrell.fastq

# move back to project directory
cd ../

# assemble genome
velveth assembly 51 -fastq data/jnorrellTrim.fastq
velvetg assembly -cov_cutoff auto -exp_cov auto

# set up read mapping, blast and results directory
mkdir mapping blast results 
cp data/referenceProject.fa mapping
cd mapping

# index reference
bwa index referenceProject.fa
samtools faidx referenceProject.fa

# map reads to contigs
bwa mem -t 8 referenceProject.fa ../data/jnorrell.fastq > reference.sam

# convert sam to sorted bam format
samtools view -bS reference.sam | samtools sort - reference.sorted

# print simple summary statistics for read mapping
samtools flagstat reference.sorted.bam > ../results/reference.flagstat.txt

# add depth of coverage to summary file
samtools depth reference.sorted.bam | awk '{sum+=$3} END { print "Average coverage= ",sum/NR}' >> ../results/reference.flagstat.txt

# find SNPs in reads relative to reference
samtools mpileup -uf referenceProject.fa reference.sorted.bam | $WORK/myapps/bcftools view - > var.raw.bcf

# filter SNPs
$WORK/myapps/bcftools view var.raw.bcf | $WORK/myapps/vcfutils.pl varFilter -D100 > var.flt.vcf

# summarize SNPs
echo -e "QUAL\t#non-indel\t#SNPs\t#transitions\t#joint\tts/tv\t#joint/#ref #joint/#non-indel" > ../results/snps.out.txt
$WORK/myapps/vcfutils.pl qstats var.flt.vcf >> ../results/snps.out.txt

# move to blast directory
cd ../blast

# copy fasta files over
cp ../data/*.fa .
mv ../assembly/contigs.fa .

# set up for loop for blasting
for fasta in referenceProject.fa contigs.fa
	do
		echo $fasta
		# make blast database 
		makeblastdb -in $fasta -dbtype nucl
		# search sequence for selected genes
		tblastn -query genesProject.fa -db $fasta -outfmt 7 -out ../results/$fasta.blast.txt
done

#counting number of contigs
grep ">" contigs.fa | wc -l > ../results/contigsNumber.txt 
