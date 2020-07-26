#!/bin/bash

# script name: akslabs.sh
# Version v0.1.4 20200726
# Set of tools to deploy AKS troubleshooting labs

# "-l|--lab" Lab scenario to deploy (5 possible options)
# "-r|--region" region to deploy the resources
# "-u|--user" User alias to add on the lab name
# "-h|--help" help info
# "--version" print version

# read the options
TEMP=`getopt -o g:n:l:r:u:hv --long resource-group:,name:,lab:,region:,user:,help,validate,version -n 'akslabs.sh' -- "$@"`
eval set -- "$TEMP"

# set an initial value for the flags
RESOURCE_GROUP=""
CLUSTER_NAME=""
LAB_SCENARIO=""
USER_ALIAS=""
LOCATION="eastus2"
VALIDATE=0
HELP=0
VERSION=0

while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -g|--resource-group) case "$2" in
            "") shift 2;;
            *) RESOURCE_GROUP="$2"; shift 2;;
            esac;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) CLUSTER_NAME="$2"; shift 2;;
            esac;;
        -l|--lab) case "$2" in
            "") shift 2;;
            *) LAB_SCENARIO="$2"; shift 2;;
            esac;;
        -r|--region) case "$2" in
            "") shift 2;;
            *) LOCATION="$2"; shift 2;;
            esac;;
        -u|--user) case "$2" in
            "") shift 2;;
            *) USER_ALIAS="$2"; shift 2;;
            esac;;    
        -v|--validate) VALIDATE=1; shift;;
        --version) VERSION=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 3 ;;
    esac
done

# Variable definition
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
SCRIPT_VERSION="Version v0.1.4 20200726"

# Funtion definition

# az login check
function az_login_check () {
    if $(az account list 2>&1 | grep -q 'az login')
    then
        echo -e "\nError: You have to login first with the 'az login' command before you can run this lab tool\n"
        az login -o table
    fi
}

# check resource group and cluster
function check_resourcegroup_cluster () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    RG_EXIST=$(az group show -g $RESOURCE_GROUP &>/dev/null; echo $?)
    if [ $RG_EXIST -ne 0 ]
    then
        echo -e "\nCreating resource group ${RESOURCE_GROUP}...\n"
        az group create --name $RESOURCE_GROUP --location $LOCATION &>/dev/null
    else
        echo -e "\nResource group $RESOURCE_GROUP already exists...\n"
    fi

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -eq 0 ]
    then
        echo -e "\nCluster $CLUSTER_NAME already exists...\n"
        echo -e "Please remove that one before you can proceed with the lab.\n"
        exit 4
    fi
}

# validate cluster exists
function validate_cluster_exists () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -ne 0 ]
    then
        echo -e "\nERROR: Fail to create cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP ...\n"
        exit 5
    fi
}

# Lab scenario 1
function lab_scenario_1 () {
    CLUTER_NAME=aks-ex1-${USER_ALIAS}
    RESOURE_GROUP=aks-ex1-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURE_GROUP $CLUTER_NAME

    echo -e "Deploying cluster for lab1...\n"
    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION_NAME \
    --node-count 1 \
    --node-vm-size Standard_B2s \
    --node-osdisk-size 50 \
    --generate-ssh-keys \
    --tag akslab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists $RESOURE_GROUP $CLUTER_NAME

    echo -e "\n\nPlease wait while we are preparing the environment for you to troubleshoot..."
    az aks get-credentials -g $RESOURE_GROUP -n $CLUTER_NAME --overwrite-existing
    SP_ID=$(az aks show -g $RESOURE_GROUP -n $CLUTER_NAME --query servicePrincipalProfile.clientId -o tsv)
    USER_ID=$(az ad user list --filter "startswith(userPrincipalName,'${USER_ALIAS}@microsoft.com')" -o tsv --query [].objectId)
    az ad app owner add --id $SP_ID --owner-object-id $USER_ID 
    SP_SECRET=$(az ad sp credential reset --name $SP_ID --query password -o tsv)
    az aks scale -g $RESOURE_GROUP -n $CLUTER_NAME -c 2

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "Case 1 is ready, cluster not able to scale...\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

# Lab scenario 2
function lab_scenario_2 () {
    CLUTER_NAME=aks-ex2-${USER_ALIAS}
    RESOURE_GROUP=aks-ex2-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURE_GROUP $CLUTER_NAME

    az aks create \
    --resource-group $RESOURE_GROUP \
    --name $CLUTER_NAME \
    --location $LOCATION \
    --node-count 1 \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists $RESOURE_GROUP $CLUTER_NAME
    
    VM_NAME=testvm1
    VM_RESOURE_GROUP=vm-test-rg-${USER_ALIAS}
    MC_RESOURCE_GROUP=$(az aks show -g $RESOURE_GROUP -n $CLUTER_NAME --query nodeResourceGroup -o tsv)
    #SUBNET_ID=$(az network vnet list -g $MC_RESOURCE_GROUP --query '[].subnets[].id' -o tsv)
    SUBNET_NAME=$(az network vnet list -o table | grep $MC_RESOURCE_GROUP | awk '{print $1}')
    SUBNET_ID=$(az network vnet show -g $MC_RESOURCE_GROUP -n $SUBNET_NAME --query subnets[].id -o tsv)

    az group create --name $VM_RESOURE_GROUP --location $LOCATION
    az vm create \
    -g $VM_RESOURE_GROUP \
    -n $VM_NAME \
    --image UbuntuLTS \
    --size Standard_B1s \
    --subnet $SUBNET_ID \
    --admin-username azureuser \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    az group delete -g $RESOURE_GROUP -y --no-wait
    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n\n********************************************************"
    echo -e "\nIt seems cluster is stuck in delete state...\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

# Lab scenario 3
function lab_scenario_3 () {
    CLUTER_NAME=aks-ex3-${USER_ALIAS}
    RESOURE_GROUP=aks-ex3-rg-${USER_ALIAS}
    VNET_NAME=aks-vnet-ex3-${USER_ALIAS}
    SUBNET_NAME=aks-subnet-ex3-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURE_GROUP $CLUTER_NAME

    az network vnet create \
    --resource-group $RESOURE_GROUP \
    --name $VNET_NAME \
    --address-prefixes 192.168.0.0/16 \
    --dns-servers 172.20.50.2 \
    --subnet-name $SUBNET_NAME \
    --subnet-prefix 192.168.100.0/24 \
    -o table
	
    SUBNET_ID=$(az network vnet subnet list \
    --resource-group $RESOURE_GROUP \
    --vnet-name $VNET_NAME \
    --query [].id --output tsv)

    az aks create \
    --resource-group $RESOURE_GROUP \
    --name $CLUTER_NAME \
    --location $LOCATION \
    --kubernetes-version 1.15.7 \
    --node-count 2 \
    --node-osdisk-size 50 \
    --node-vm-size Standard_B2s \
    --network-plugin azure \
    --service-cidr 10.0.0.0/16 \
    --dns-service-ip 10.0.0.10 \
    --docker-bridge-address 172.17.0.1/16 \
    --vnet-subnet-id $SUBNET_ID \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists $RESOURE_GROUP $CLUTER_NAME

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo "Cluster deployment failed...\n"
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

# Lab scenario 4
function lab_scenario_4 () {
    CLUSTER_NAME=aks-ex4-${USER_ALIAS}
    RESOURCE_GROUP=aks-ex4-rg-${USER_ALIAS}
    VNET_NAME=aks-ex4-vnet-${USER_ALIAS}
    SUBNET_NAME=aks-ex4-subnet-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURE_GROUP $CLUTER_NAME

    az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name $VNET_NAME \
    --address-prefixes 10.77.16.0/20 \
    --subnet-name $SUBNET_NAME \
    --subnet-prefix 10.77.17.0/24
        
    SUBNET_ID=$(az network vnet subnet list \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --query [].id --output tsv)

    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --vm-set-type AvailabilitySet \
    --load-balancer-sku basic \
    --max-pods 100 \
    --network-plugin azure \
    --service-cidr 10.0.0.0/16 \
    --dns-service-ip 10.0.0.10 \
    --docker-bridge-address 172.17.0.1/16 \
    --vnet-subnet-id $SUBNET_ID \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists $RESOURE_GROUP $CLUTER_NAME

    az aks upgrade -g $RESOURCE_GROUP -n $CLUSTER_NAME -y
    echo -e "\n\nCluster in failed state after upgrade...\n"
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

# Lab scenario 5
function lab_scenario_5 () {
    CLUTER_NAME=aks-ex5-${USER_ALIAS}
    RESOURE_GROUP=aks-ex5-rg1-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURE_GROUP $CLUTER_NAME

    az aks create \
    --resource-group $RESOURE_GROUP \
    --name $CLUTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --node-osdisk-size 30 \
    --max-pods 100 \
    --node-vm-size Standard_B2ms \
    --enable-addons monitoring \
    --generate-ssh-keys \
    --tag l200lab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists $RESOURE_GROUP $CLUTER_NAME

    echo -e "\nCompleting the lab setup..."
    az aks get-credentials -g $RESOURE_GROUP -n $CLUTER_NAME --overwrite-existing
    kubectl apply -f https://raw.githubusercontent.com/sturrent/aks-troubleshooting-labs/master/stress-io.yaml
    sleep 120s
    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n\nThere are issues with nodes in NotReady state...\n"
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

#if -h | --help option is selected usage will be displayed
if [ $HELP -eq 1 ]
then
	echo -e "akslabs usage: akslabs -l <LAB#> -u <USER_ALIAS>[-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Scale action failed (SP issues)
*\t 2. Cluster failed to delete
*\t 3. Cluster deployment failed
*\t 4. Cluster failed after upgrade
*\t 5. Cluster with nodes not ready
***************************************************************\n"
    echo -e '""-l|--lab" Lab scenario to deploy (5 possible options)
"-r|--region" region to create the resources
"--version" print version of akslabs
"-h|--help" help info\n'
	exit 0
fi

if [ $VERSION -eq 1 ]
then
	echo -e "$SCRIPT_VERSION\n"
	exit 0
fi

if [ -z $LAB_SCENARIO ]; then
	echo -e "Error: Lab scenario value must be provided. \n"
	echo -e "akslabs usage: akslabs -l <LAB#> -u <USER_ALIAS>[-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Scale action failed (SP issues)
*\t 2. Cluster failed to delete
*\t 3. Cluster deployment failed
*\t 4. Cluster failed after upgrade
*\t 5. Cluster with nodes not ready
***************************************************************\n"
	exit 9
fi

if [ -z $USER_ALIAS ]; then
	echo -e "Error: User alias value must be provided. \n"
	echo -e "akslabs usage: akslabs -l <LAB#> -u <USER_ALIAS>[-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Scale action failed (SP issues)
*\t 2. Cluster failed to delete
*\t 3. Cluster deployment failed
*\t 4. Cluster failed after upgrade
*\t 5. Cluster with nodes not ready
***************************************************************\n"
	exit 10
fi

# lab scenario has a valid option
if [[ ! $LAB_SCENARIO =~ ^[1-5]+$ ]];
then
    echo -e "\nError: invalid value for lab scenario '-l $LAB_SCENARIO'\nIt must be value from 1 to 5\n"
    exit 11
fi

# main
echo -e "\nAKS Troubleshooting sessions
********************************************

This tool will use your internal azure account to deploy the lab environments.
Verifing if you are authenticated already...\n"

# Verify az cli has been authenticated
az_login_check

if [ $LAB_SCENARIO -eq 1 ]
then
    lab_scenario_1

elif [ $LAB_SCENARIO -eq 2 ]
then
    lab_scenario_2

elif [ $LAB_SCENARIO -eq 3 ]
then
    lab_scenario_3

elif [ $LAB_SCENARIO -eq 4 ]
then
    lab_scenario_4

elif [ $LAB_SCENARIO -eq 5 ]
then
    lab_scenario_5

else
    echo -e "\nError: no valid option provided\n"
    exit 12
fi

exit 0