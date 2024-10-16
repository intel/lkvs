import subprocess

cpu_family_mapping = {
    "SPR" : {0x8F, 143},
    "EMR" : {0xCF, 207},
    "GNR" : {0xAD, 173},
    "SRF" : {0xAF, 175},
    "CWF" : {0xDD, 221}
}

feature_list = {
    "AESNI": {
        "cpuid": ['1', '0', '0', '0', 'c', '25'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "XSAVE": {
        "cpuid": ['1', '0', '0', '0', 'c', '26'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "FSGSBASE": {
        "cpuid": ['7', '0', '0', '0', 'b', '0'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "SMEP": {
        "cpuid": ['7', '0', '0', '0', 'b', '7'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "RDT_A": {
        "cpuid": ['7', '0', '0', '0', 'b', '15'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "AVX512_IFMA": {
        "cpuid": ['7', '0', '0', '0', 'b', '21'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "SHA_NI": {
        "cpuid": ['7', '0', '0', '0', 'b', '29'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "AVX512_VBMI": {
        "cpuid": ['7', '0', '0', '0', 'c', '1'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "UMIP": {
        "cpuid": ['7', '0', '0', '0', 'c', '2'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "WAITPKG": {
        "cpuid": ['7', '0', '0', '0', 'c', '5'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "AVX512_VBMI2": {
        "cpuid": ['7', '0', '0', '0', 'c', '6'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "CET_SS": {
        "cpuid": ['7', '0', '0', '0', 'c', '7'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "GFNI": {
        "cpuid": ['7', '0', '0', '0', 'c', '8'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "VAES": {
        "cpuid": ['7', '0', '0', '0', 'c', '9'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "VPCLMULQDQ": {
        "cpuid": ['7', '0', '0', '0', 'c', '10'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "AVX512_VNNI": {
        "cpuid": ['7', '0', '0', '0', 'c', '11'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "AVX512_BITALG": {
        "cpuid": ['7', '0', '0', '0', 'c', '12'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "RDPID": {
        "cpuid": ['7', '0', '0', '0', 'c', '22'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "KL": {
        "cpuid": ['7', '0', '0', '0', 'c', '23'],
        "platforms": {}
    },
    "CLDEMOTE": {
        "cpuid": ['7', '0', '0', '0', 'c', '25'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "MOVDIRI": {
        "cpuid": ['7', '0', '0', '0', 'c', '27'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "MOVDIR64B": {
        "cpuid": ['7', '0', '0', '0', 'c', '28'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "PKS": {
        "cpuid": ['7', '0', '0', '0', 'c', '31'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "UINTR": {
        "cpuid": ['7', '0', '0', '0', 'd', '5'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "AVX512_VP2INTERSECT": {
        "cpuid": ['7', '0', '0', '0', 'd', '8'],
        "platforms": {}
    },
    "SERIALIZE": {
        "cpuid": ['7', '0', '0', '0', 'd', '14'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "TSXLDTRK": {
        "cpuid": ['7', '0', '0', '0', 'd', '16'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "CET_IBT": {
        "cpuid": ['7', '0', '0', '0', 'd', '20'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "AMX_BF16": {
        "cpuid": ['7', '0', '0', '0', 'd', '22'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "AVX512_FP16": {
        "cpuid": ['7', '0', '0', '0', 'd', '23'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "AMX_TILE": {
        "cpuid": ['7', '0', '0', '0', 'd', '24'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "AMX_INT8": {
        "cpuid": ['7', '0', '0', '0', 'd', '25'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "AVX_VNNI": {
        "cpuid": ['7', '0', '1', '0', 'a', '4'],
        "platforms": {"SPR", "EMR", "GNR", "SRF", "CWF"}
    },
    "CMPCCXADD": {
        "cpuid": ['7', '0', '1', '0', 'a', '7'],
        "platforms": {"SRF", "CWF"}
    },
    "FRED": {
        "cpuid": ['7', '0', '1', '0', 'a', '17'],
        "platforms": {"CWF"}
    },
    "WRMSRNS": {
        "cpuid": ['7', '0', '1', '0', 'a', '19'],
        "platforms": {"SRF", "CWF"}
    },
    "AMX_FP16": {
        "cpuid": ['7', '0', '1', '0', 'a', '21'],
        "platforms": {"GNR"}
    },
    "AVX_IFMA": {
        "cpuid": ['7', '0', '1', '0', 'a', '23'],
        "platforms": {"SRF", "CWF"}
    },
    "AVX_VNNI_INT8": {
        "cpuid": ['7', '0', '1', '0', 'd', '4'],
        "platforms": {"SRF", "CWF"}
    },
    "AVX_NE_CONVERT": {
        "cpuid": ['7', '0', '1', '0', 'd', '5'],
        "platforms": {"SRF", "CWF"}
    },
    "PREFETCHI": {
        "cpuid": ['7', '0', '1', '0', 'd', '14'],
        "platforms": {"GNR"}
    },
    "XFD": {
        "cpuid": ['d', '0', '1', '0', 'a', '4'],
        "platforms": {"SPR", "EMR", "GNR"}
    },
    "KL_BITMAP0": {
        "cpuid": ['19', '0', '0', '0', 'a', '0'],
        "platforms": {}
    },
    "KL_BITMAP1": {
        "cpuid": ['19', '0', '0', '0', 'a', '1'],
        "platforms": {}
    },
    "KL_BITMAP2": {
        "cpuid": ['19', '0', '0', '0', 'a', '2'],
        "platforms": {}
    },
    "AESKLE": {
        "cpuid": ['19', '0', '0', '0', 'b', '0'],
        "platforms": {}
    },
    "AES_WIDE": {
        "cpuid": ['19', '0', '0', '0', 'b', '2'],
        "platforms": {}
    },
    "KL_IWKEYBACKUP": {
        "cpuid": ['19', '0', '0', '0', 'b', '4'],
        "platforms": {}
    },
    "KL_RANDOM_IWKEY": {
        "cpuid": ['19', '0', '0', '0', 'c', '1'],
        "platforms": {}
    }
    # Add more feature_info here
}

def get_cpu_family_id():
    # Run the 'lscpu' command and capture its output
    result = subprocess.run(['/usr/bin/lscpu'], capture_output=True, text=True, check=True)

    # Split the output into lines
    output_lines = result.stdout.splitlines()

    # Find the line containing "Model:" and extract the family ID
    for line in output_lines:
        if "Model:" in line:
            # Assuming the family ID follows 'Model:' and is separated by spaces
            family_id = line.split(':')[1].strip()
            return int(family_id)

def get_platform():
    cpu_family_id = get_cpu_family_id()
    platform = None
    for key, values in cpu_family_mapping.items():
        if cpu_family_id in values:
            platform = key
            break
    return platform
