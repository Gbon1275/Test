provider "azurerm" {
    # not needed but good practise
    version = "2.9.0"
    features {}
}

# resource group
resource "azurerm_resource_group" "ApiRG" {
    name = "APIRG1"
    location = "Germany North"
}

#security group
resource "azurerm_network_security_group" "ApiNsg" {
    name = "NSG1"
    location = azurerm_resource_group.location
    resource_group_name = azurerm_resource_group.ApiRG.Name
}

# virtual Network
resource "azurerm_virtual_network" "APIVnet" {
    name = "apiVnet"
    address_space  = ["192.168.1.0/24"]
    location = azurerm_resource_group.ApiRG.location
    resource_group_name = azurerm_resource_group.ApiRG.name
}

# Subnet
resource "azurerm_subnet" "APISNet" {
    name = apisnet
    resource_group_name = azurerm_resource_group.ApiRG.name
    virtual_network_name = azurerm_virtual_network.apiVnet.name
    address_prefix = "192,168.1.16/28"
}

# NICs for VM
resource "azurerm_network_interface" "ApiNic" {
    count = 2
    name = "apinic${count.index + 1}"
    location = azurerm_resource_group.ApiRG.location
    resource_group_name =azurerm_resource_group.ApiRG.name

    ip_configuration{
        name = "ipconfig"
        subnet_is = azurerm_subnet.APISNet.id
        private_ip_address_allocation = "dynamic"
    }
}

# VM Data Disk
resource "azurerm_managed_disk" "ApiVmDisk" {
    count = 2
    name = "api_node_data_disk${count.index}"
    location = azurerm_resource_group.ApiRG.location
    resource_name_group = azurerm_resource_group.ApiRG.name
    storage_account_type = "Standard_LRS"
    create_option = "Empty"
    disk_size_gb = "50"
}

# Virtual Machine
resource "azurerm_virtual_machine" "ApiVm" {
    count = 2
    name = "apiVM0${count.index + 1 }"
    location = azurerm_resource_group.ApiRG.location
    resource_group_name = azurerm_resource_group.ApiRG.name
    network_interface_ids = [element(azurerm_network_interface.ApiNic.*, count.index)]
    vm_size = "standard_DS1_V2"

    delete_os_disk_on_termination = true
    delete_data_disk_on_termination = true

    storage_image_reference {
        publisher = "Canonical"
        offer = "UbuntuServer"
        sku = "16.04-LTS"
    }

    storage_os_disk {
        name = "apiVMos${count.index}"
        caching = "ReadWrite"
        create_option = "FromImage"
        managed_disk_type = "Standard_LRS"
    }

    storage_data_disk {
        name = element(azurerm_managed_disk.ApiVmDisk.*.name, count.index)
        managed_disk_id = element(azurerm_managed_disk.ApiVmDisk.*.id, count.index)
        create_option = "Attach"
        lun = 1
        disk_size_gb = element(azurerm_managed_disk.ApiVmDisk.*.disk_size_gb, count.index)
   }

    os_profile {
        computer_name = "hostname"
        admin_username = "admin"
        admin-password = "adminPassword"
    }

    os_profile_linux_config {
        disable_passowrd_authentication = false
    }

    tages = {
        env = "ApiNode"
    }
}

resource "azurerm_network_interface_security_group_association" {
    count = 2
    network_interface_id = "${element(azurerm_network_interface.ApiNic.*.id , count.index + 1)}"
    network_security_group_id = azurerm_network_security_group.ApiNsg.id
}

resource "azurerm_public_ip" "ApiPubIP" {
    name = "apipubip"
    location = azurerm_resource_group.ApiRG.location
    resource_group_name = azurerm_resource_group.ApiRG.name
    allocation_method = "static"
}

resource "azurerm_lb" "ApiLb" {
    name = "ApiLB01"
    location = azure_resource_group.ApiRG.location
    resource_group_name = azurerm_resource_group.ApiRG.name

    frontend_ip_configuration {
        name = "PublicIP1"
        public_ip_address_id = azurerm_public_ip.ApiPubIP.id
    }
}

resource "azurerm_lb_backend_address_pool" "ApiLbPool" {
    loadbalancer_id = azurerm_lb.ApiLb.id
    resource_group_name = azure_resource_group.ApiRG.name
    name = "ApiNodePool"
}

resource "azurerm_network_interface_backend_address_pool_association" "apipoolassign" {
    count = 2
    network_interfaace_id = "${element(azurerm_network_interface.ApiNic.*.id, count.index)}"
    ip_configuration_name = "nic_ip_config"
    backend_address_pool_id = azurerm_lb_backend_address_pool.ApiLbPool.id
}