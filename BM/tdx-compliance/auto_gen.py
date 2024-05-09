

# related filepath
import csv
import sys
import re
import pandas
import math
import json

# some parse func
def parse_leaf(field_name):
    match_leaves = re.search(r'Leaf (\w+)', field_name)
    match_subleafs = re.search(r'Sub-Leaves (\w+-\w+)', field_name)
    match_subleaf = re.search(r'Sub-Leaf (\w+)', field_name)

    if match_leaves:
        leaf = match_leaves.group(1)
    else:
        return None, None

    if match_subleafs:
        subleaves_range = match_subleafs.group(1).split('-')
        subleaves = [str(hex(i)) for i in range(int(subleaves_range[0], 16), int(subleaves_range[1], 16) + 1)]
    elif match_subleaf:
        subleaves = [match_subleaf.group(1)]
    else:
        subleaves = ["0x0"]

    return leaf, subleaves

def get_valstr(str_wait, column_indices):
    virt = None
    for v in str_wait:
        if v in column_indices:
            virt = v
            break
    return virt

class GenCase:
    def __init__(self, config_path):
        self.config_path = config_path
        self.ptype = ""
        self.csv_path = ""
        self.header_path = ""
        self.bias = "0"
        self.version = "1.0"
        self.ans = []
        self.body = []
        self.config = {}

    def read_config(self):
        try:
            with open(self.config_path, 'r') as config_file:
                origin_data = json.load(config_file)
                self.config = origin_data.get(self.ptype, {})
                self.csv_path = self.config.get("csv_path", None)
                self.header_path = self.config.get("header_path", None)
                self.bias = self.config.get("bias", "0")
                self.version = self.config.get("version", "1.0")
        except Exception as e:
            raise Exception(f"Failed to parse config: {e}")

    def read_spec(self):
        try:
            df = pandas.read_csv(self.csv_path, skiprows=range(int(self.bias)))
            columns = df.columns.tolist()
            column_indices = {column: index for index, column in enumerate(columns)}
            return df, columns, column_indices
        except Exception as e:
            raise Exception(f"Failed to get csv_index: {e}")

    def write2header(self, funcName="initial_cpuid"):
        function_name = f"void {funcName}(void)"
        try:
            with open(self.header_path, 'w') as header_file:
                header_file.write(f"#define AUTOGEN_{self.ptype.upper()}\n")
                for line in self.body:
                    header_file.write(line + '\n')
        except Exception as e:
            raise Exception(f"Failed to write to header file: {e}")

class CpuidCase(GenCase):
    def __init__(self, config_path):
        super().__init__(config_path)
        self.ptype = "cpuid"

        # 定义cpuid独属的csv的目录项
        self.vDetail = ""
        self.vType = ""
        self.fName = ""
        try:
            self.read_config()
            self.init_param()
        except Exception as e:
            print(f"Failed to initialize GenCase: {e}")
            raise

    def init_param(self):
        self.vDetail = self.config.get("vdetail", [])
        self.vType = self.config.get("vtype", [])
        self.fName = self.config.get("fname", "")

    def parse_csv(self):
        self.ans = []
        df, columns, column_indices = self.read_spec()
        self.vType = get_valstr(self.vType, column_indices)
        self.vDetail = get_valstr(self.vDetail, column_indices)

        leaf = ""
        subleaf = []
        isNew = ""
        for index, row in df.iterrows():
            field_name = row[columns[column_indices[self.fName]]]
            virt_type = row[columns[column_indices[self.vType]]]
            virt_detail = str(row[columns[column_indices[self.vDetail]]])
            reg = row[columns[column_indices['Reg.']]]

            if isinstance(reg, float) and math.isnan(reg):
                leaf, subleaf = parse_leaf(field_name)
                isNew = field_name
            elif virt_type == 'Fixed':
                msb = int(row[columns[column_indices['MSB']]])
                lsb = int(row[columns[column_indices['LSB']]])
                field_size = int(row[columns[column_indices['Field Size']]])

                if isNew != "":
                    self.ans.append([-1,-1,-1,-1,-1,-1,isNew,-1])
                    isNew = ""
                entry = []
                """ archived, replaced by parse_leaf
                leaf = row[columns[column_indices['Leaf']]]
                sl_from = row[columns[column_indices['Sub-Leaf From']]]
                sl_to = row[columns[column_indices['Sub-Leaf To']]]
                if isinstance(sl_from, float) and math.isnan(sl_from):
                    sl_from = 0x0
                    sl_to = 0x0
                else:
                    sl_from = int(sl_from, 16)
                    sl_to = int(sl_to, 16)
                """
                for i in subleaf:
                    entry = [leaf, i, reg, msb, lsb, field_size, field_name, virt_detail]
                    self.ans.append(entry)

    def get_body(self):
        self.body = []
        self.body.append("void initial_cpuid(void) {")
        for entry in self.ans:
            leaf = entry[0]
            subleaf = entry[1]
            reg = entry[2]
            msb = entry[3]
            lsb = entry[4]
            size = entry[5]
            name = entry[6]
            val = entry[7]
            if entry[5] == -1:
                self.body.append("\n\t// %s" % (name))
            elif entry[5] == 32:
                self.body.append("\tEXP_CPUID_BYTE(%s, %s, %s, %s, %s);\t//%s" % ( \
                    leaf, subleaf, reg, val, self.version, name))

            elif entry[5] == 1:
                self.body.append("\tEXP_CPUID_BIT(%s, %s, %s, %s, %s, %s);\t//%s" % ( \
                    leaf, subleaf, reg, msb, val, self.version, name))
            else:
                self.body.append("\tEXP_CPUID_RES_BITS(%s, %s, %s, %s, %s, %s);\t//%s" % ( \
                    leaf, subleaf, reg, lsb, msb, self.version, name))
        self.body.append("}")

class MsrCase(GenCase):
    def __init__(self, config_path):
        super().__init__(config_path)
        self.ptype = "msr"

        # 定义msr独属的csv的目录项
        self.vDetail = ""
        self.rdName = ""
        self.wrName = ""
        try:
            self.read_config()
            self.init_param()
        except Exception as e:
            print(f"Failed to initialize GenCase: {e}")
            raise

    def init_param(self):
        self.vDetail = self.config.get("vdetail", [])
        self.rdName = self.config.get("rdnmae", [])
        self.wrName = self.config.get("wrname", [])

    def parse_csv(self):
        self.ans = []
        df, columns, column_indices = self.read_spec()
        self.rdName = get_valstr(self.rdName, column_indices)
        self.wrName = get_valstr(self.rdName, column_indices)

        for index, row in df.iterrows():
            rd_ept = row[columns[column_indices[self.rdName]]]
            wr_ept = row[columns[column_indices[self.wrName]]]
            virt_detail = str(row[columns[column_indices[self.vDetail]]])




def write2header(path, list, ptype, funcName="initial_cpuid"):
    """
    gen a header file
    :param path:
    :param list: stores the generated statements for all cases.
    :param funcName: the initial-func name defined in header file.
    :return: if -1 is returned, it means the write failed
    """
    function_name = f"void {funcName}(void)"
    ptype = ptype.upper()
    try:
        with open(path, 'w') as header_file:
            header_file.write(f"#define AUTOGEN_{ptype}\n\n")
            header_file.write(f"{function_name} {{\n")

            for line in list:
                header_file.write('\t' + line + '\n')
            header_file.write("}\n")
        return 0
    except:
        return -1

if __name__ == '__main__':

    # init all params
    config_path = 'config.json'
    cpuid_case = CpuidCase(config_path)
    cpuid_case.parse_csv()

    if not cpuid_case.ans:
        print("Failed to parse csv. Exiting program.")
        sys.exit(1)
    #assert get_csv.ans, "ans is empty. Exiting program."
    cpuid_case.get_body()

    #gen a header file
    cpuid_case.write2header()






