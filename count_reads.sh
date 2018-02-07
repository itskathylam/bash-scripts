#!/usr/bin/bash

# Author: Kathy N Lam
# Purpose: hacky way to count reads in a fastq file

files=($(ls reads))
for file in "${files[@]}"
    
#method: grep for + with start/end anchors   
do
    echo $file
    records=$( zcat reads/$file | grep "^+$" | wc -l )
    echo $records
done

