#!/bin/python
import re
import pandas
import math
import json

pre_dict = {}
func_names = []
pattern = r'static\s+void\s+(\w+)\s*\(struct\s+test_msr\s*\*\s*c\)'

def checkdef(funcName):
    if func_names is not None:
        if funcName in func_names:
            return True
    return False

# some parse func
def extract_func_name(file_path):
    func_names = []

    try:
        with open(file_path, 'r') as file:
            content = file.read()
            matches = re.finditer(pattern, content)

            for match in matches:
                func_name = match.group(1)
                func_names.append(func_name)

    except FileNotFoundError:
        print(f"File not found: {file_path}")
    except Exception as e:
        print(f"An error occurred: {e}")

    return func_names

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
        if match_subleaf.group(1) == "N":
            subleaves = ["0x0"]
        else:
            subleaves = [match_subleaf.group(1)]
    else:
        subleaves = ["0x0"]

    return leaf, subleaves

def parse_msrvirt(virtdesc):
    if virtdesc.startswith("native") or virtdesc.startswith("Native"):
        return True, "NO_EXCP", "NO_PRE_COND"
    elif virtdesc.startswith("#GP(0)"):
        return True, "X86_TRAP_GP", "NO_PRE_COND"
    elif virtdesc.startswith("#VE"):
        return True, "X86_TRAP_VE", "NO_PRE_COND"
    elif virtdesc.startswith("Inject_GP("):
        return gen_gp(trimbracket(virtdesc))
    elif virtdesc.startswith("Inject_GP_or_VE"):
        return gen_ve(trimbracket(virtdesc))
    else:
        return False, "", ""

def trimbracket(virtdesc):
    count = 0
    start = -1
    result = ""

    for i, char in enumerate(virtdesc):
        if char == '(':
            if count == 0:
                start = i+1
            count += 1
        elif char == ')':
            count -= 1
            if count == 0:
                result = virtdesc[start:i].strip()
                break

    return result

def gen_rst(virtdesc, exception_type):
    pre_value = "Invalid Generator"
    if pre_dict.get(virtdesc) is not None:
        tmp = pre_dict.get(virtdesc)
        if checkdef(tmp):
            pre_value = tmp
        else:
            print(f"This pre_condition is undefined: {virtdesc}")
            return False, "NO_EXCP", pre_value
    else:
        print(f"This pre_condition is undefined: {virtdesc}")
        return False, "NO_EXCP", pre_value

    return True, exception_type, pre_value

def gen_gp(virtdesc):
    return gen_rst(virtdesc, "X86_TRAP_GP")

def gen_ve(virtdesc):
    return gen_rst(virtdesc, "X86_TRAP_VE")

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
        self.spec_list = []
        self.ptype = ""
        self.csv_path = ""
        self.header_path = ""
        self.bias = "0"
        self.version = "VER1_0"
        self.ans = []
        self.body = []
        self.config = {}

    def read_config(self):
        try:
            with open(self.config_path, 'r') as config_file:
                origin_data = json.load(config_file)
                self.config = origin_data.get(self.ptype, {})
                self.header_path = self.config.get("header_path", None)
                self.spec_list = self.config.get('spec_list', [])

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

    def getparam(self, item):
        pass

    def write2header(self):
        try:
            with open(self.header_path, 'w') as header_file:
                header_file.write(f"#define AUTOGEN_{self.ptype.upper()}\n")
                for line in self.body:
                    header_file.write(line + '\n')
        except Exception as e:
            raise Exception(f"Failed to write to header file: {e}")

    def get_body(self):
        pass

    def parse_csv(self):
        pass

    #核心方法
    def autorun(self):
        i = 0
        for item in self.spec_list:
            self.getparam(item)
            self.parse_csv()
            if i:
                self.fusion()
                self.ans[0] = self.sort_by_spec(self.ans[0])
            i += 1
        self.get_body()
        self.write2header()

    #融合相关
    def fusion(self):
        if self.ans is None:
            return
        for it1 in self.ans[1:]:
            for it2 in it1:
                self.compre(it2)

    def compre(self, iter):
        pass

    def sort_by_spec(self, arr):
        pass

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
            self.fName = self.config.get("fname", "Field Name")
        except Exception as e:
            print(f"Failed to initialize GenCase: {e}")
            raise

    def getparam(self, item):
        self.csv_path = item.get("csv_path", None)
        self.bias = item.get("bias", "0")
        self.vType = item.get("vtype", "Virtualization Details")
        self.vDetail = item.get("vdetail", "Virtualization Details")
        self.version = item.get("version", "VER1_0")

    def compre(self, iter):
        match_found = False
        for it in self.ans[0]:
            if iter[:-3] == it[:-3]:
                # 跳过field_name这一项不硬要求
                if iter[-2] == it[-2]:
                    it[-1] = f"{it[-1]} | {iter[-1]}"
                    match_found = True
                    break
        if not match_found:
            self.ans[0].append(iter)

    def sort_by_spec(self, arr):
        leaf_order = {'-1': -1, 'eax': 0, 'ebx': 1, 'ecx': 2, 'edx': 3}
        arr.sort(key=lambda item: (
        int(item[0], 16), int(item[1], 16), leaf_order.get(item[2], float('inf')), item[4], item[5]))
        return arr

    def parse_csv(self):
        anstmp = []
        df, columns, column_indices = self.read_spec()
        # self.vType = get_valstr(self.vType, column_indices)
        # self.vDetail = get_valstr(self.vDetail, column_indices)

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
                reg = reg.lower()

                if isNew != "":
                    anstmp.append([leaf,subleaf[0],-1,-1,-1,-1,isNew,-1, self.version])
                    isNew = ""

                for i in subleaf:
                    entry = [leaf, i, reg, msb, lsb, field_size, field_name, virt_detail, self.version]
                    anstmp.append(entry)
        self.ans.append(anstmp)

    def get_body(self):
        self.body = []
        self.body.append("void initial_cpuid(void) {")
        for entry in self.ans[0]:
            leaf = entry[0]
            subleaf = entry[1]
            reg = entry[2]
            msb = entry[3]
            lsb = entry[4]
            size = entry[5]
            name = entry[6]
            val = entry[7]
            ver = entry[8]
            if entry[5] == -1:
                self.body.append("\n\t// %s" % (name))
            elif entry[5] == 32:
                self.body.append("\tEXP_CPUID_BYTE(%s, %s, %s, %s, %s);\t//%s" % ( \
                    leaf, subleaf, reg, val, ver, name))

            elif entry[5] == 1:
                self.body.append("\tEXP_CPUID_BIT(%s, %s, %s, %s, %s, %s);\t//%s" % ( \
                    leaf, subleaf, reg, msb, val, ver, name))
            else:
                self.body.append("\tEXP_CPUID_RES_BITS(%s, %s, %s, %s, %s, %s);\t//%s" % ( \
                    leaf, subleaf, reg, lsb, msb, ver, name))
        self.body.append("}")

class MsrCase(GenCase):
    def __init__(self, config_path):
        super().__init__(config_path)
        self.ptype = "msr"

        # 定义msr独属的csv的目录项
        self.prepath = ""
        self.rdName = ""
        self.wrName = ""
        try:
            self.read_config()
            self.init_param()
        except Exception as e:
            print(f"Failed to initialize GenCase: {e}")
            raise

    def init_param(self):
        self.prepath = self.config.get("prepath", "")
        with open(self.prepath, 'r') as pre_file:
            global pre_dict
            pre_dict = json.load(pre_file)

    def getparam(self, item):
        self.csv_path = item.get("csv_path", None)
        self.bias = item.get("bias", "0")
        self.rdName = item.get("rdname", "On RDMSR")
        self.wrName = item.get("wrname", "On WRMSR")
        self.version = item.get("version", "VER1_0")

    def compre(self, iter):
        match_found = False
        for it in self.ans[0]:
            if iter[1:6] == it[1:6]:
                it[-1] = f"{it[-1]} | {iter[-1]}"
                match_found = True
                break
        if not match_found:
            self.ans[0].append(iter)

    def sort_by_spec(self, arr):
        leaf_order = {'r': 0, 'w': 1}
        arr.sort(key=lambda item: (int(item[1], 16), int(item[2], 16), leaf_order.get(item[5], float('inf'))))
        return arr

    def parse_csv(self):
        anstmp = []
        df, columns, column_indices = self.read_spec()
        # self.rdName = get_valstr(self.rdName, column_indices)
        # self.wrName = get_valstr(self.wrName, column_indices)

        for index, row in df.iterrows():
            ept = [0, 0]
            ept[0] = row[columns[column_indices[self.rdName]]]
            ept[1] = row[columns[column_indices[self.wrName]]]
            field_name = str(row[columns[column_indices['MSR Architectural Name']]])
            if field_name == "Reserved":
                continue
            if row[columns[column_indices['First (H)']]] == "Default":
                continue
            msb = str(hex(int(row[columns[column_indices['First (H)']]], 16)))
            lsb = str(hex(int(row[columns[column_indices['Last (H)']]], 16)))
            field_size = str(hex(int(row[columns[column_indices['Size (H)']]], 16)))

            for i in range(2) :
                isVaild, err_type, pre_name = parse_msrvirt(ept[i])
                if isVaild:
                    rw_type = "r" if i == 0 else "w"
                    anstmp.append([field_name, msb, field_size, err_type, pre_name, rw_type, self.version])
        self.ans.append(anstmp)

    def get_body(self):
        self.body = []
        self.body.append("struct test_msr msr_cases[] = {")
        for entry in self.ans[0]:
            name = entry[0]
            msb = entry[1]
            size = entry[2]
            err_type = entry[3]
            pre_name = entry[4]
            rw_type = entry[5]
            ver = entry[6]

            if entry[5] == 'r':
                if entry[2] == "0x1":
                    self.body.append("\tDEF_READ_MSR(\"%s\", %s, %s, %s, %s)," % (name, msb, err_type, pre_name, ver))
                else:
                    self.body.append("\tDEF_READ_MSR_SIZE(\"%s\", %s, %s, %s, %s, %s)," % (name, msb, err_type, pre_name, size, ver))
            elif entry[5] == 'w':
                if entry[2] == "0x1":
                    self.body.append("\tDEF_WRITE_MSR(\"%s\", %s, %s, %s, %s)," % (name, msb, err_type, pre_name, ver))
                else:
                    self.body.append("\tDEF_WRITE_MSR_SIZE(\"%s\", %s, %s, %s, %s, %s)," % (name, msb, err_type, pre_name, size, ver))

            else:
                print("This case is invalid:\nMSR NAME: %s; INDEX: %s; ERRTYPE: %s; PRE_CON: %s; SIZE: %s; VERSION: %s; RW: %s." % (name, msb, err_type, pre_name, size, ver, rw_type))
        self.body.append("};")

if __name__ == '__main__':

    func_names = extract_func_name("pre_condition.h")
    # init all params
    config_path = 'config.json'
    cpuid_case = CpuidCase(config_path)
    cpuid_case.autorun()
    msr_case = MsrCase(config_path)
    msr_case.autorun()







