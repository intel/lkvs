#!/bin/bash
for file in cmp*; do
    if [ -x "$file" ]; then
        echo -e "\nExecuting $file ..."
        ./"$file"
    fi
done
