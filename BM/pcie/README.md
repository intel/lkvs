# pcie related tests description

## case implemented by pcie_check.sh and pcie_check.c for general PCIe capability check
### for simplicity, only check PCIe Cap Structure (7.5.3 in spec) Max Speed, Current Speed, Supported Speed, Target Speed
  - PCIe root port (PCI bridge) Gen4 capability test, apply for PCIe Gen4 platform
  ```
    ./pcie_check.sh gen4
  ```
  - PCIe root port (PCI bridge) Gen5 capability test, apply for PCIe Gen5 platform
  ```
    ./pcie_check.sh gen5
  ```
  - PCIe root port (PCI bridge) Gen6 capability test, apply for PCIe Gen4 platform
  ```
    ./pcie_check.sh gen6
  ```
