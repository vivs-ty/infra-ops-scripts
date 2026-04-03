#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

# Usage help
usage() {
  echo ""
  echo "Terraform State Manager"
  echo ""
  echo "SYNTAX  = ./state_list.sh <COMMAND> [OPTIONS] <PATH>"
  echo ""
  echo "COMMANDS:"
  echo "  list                        <PATH>                       - List all resources in state"
  echo "  show    <RESOURCE_ADDRESS>  <PATH>                       - Show details of a specific resource"
  echo "  move    <SOURCE_ADDRESS>    <DESTINATION_ADDRESS> <PATH> - Move/rename a resource in state"
  echo "  remove  <RESOURCE_ADDRESS>  <PATH>                       - Remove a resource from state"
  echo "  pull                        <PATH>                       - Pull and display the raw state file"
  echo ""
  echo "EXAMPLES:"
  echo "  ./state_list.sh list terraform/instance"
  echo "  ./state_list.sh show aws_instance.web terraform/instance"
  echo "  ./state_list.sh move aws_instance.old aws_instance.new terraform/instance"
  echo "  ./state_list.sh remove aws_instance.web terraform/instance"
  echo "  ./state_list.sh pull terraform/instance"
  echo ""
  exit 1
}

######################################################################################

COMMAND="$1"

if [[ -z "$COMMAND" ]]; then
  usage
fi

######################################################################################

case "$COMMAND" in

  list)
    TERRAFORM_PATH="$2"
    if [[ -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide a Terraform path."
      usage
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "Resources in state for: $TERRAFORM_PATH"
    echo "------------------------------------------------------------"
    terraform state list "$TERRAFORM_PATH"
    ;;

  show)
    RESOURCE_ADDRESS="$2"
    TERRAFORM_PATH="$3"
    if [[ -z "$RESOURCE_ADDRESS" || -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide a resource address and Terraform path."
      usage
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "State details for resource: $RESOURCE_ADDRESS"
    echo "------------------------------------------------------------"
    if ! terraform state show -state="$TERRAFORM_PATH/terraform.tfstate" "$RESOURCE_ADDRESS"; then
      echo "ERROR: Resource '$RESOURCE_ADDRESS' not found in state."
      echo "Run './state_list.sh list $TERRAFORM_PATH' to see all resources."
      exit 1
    fi
    ;;

  move)
    SOURCE_ADDRESS="$2"
    DESTINATION_ADDRESS="$3"
    TERRAFORM_PATH="$4"
    if [[ -z "$SOURCE_ADDRESS" || -z "$DESTINATION_ADDRESS" || -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide source address, destination address, and Terraform path."
      usage
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "Moving resource in state:"
    echo "  FROM : $SOURCE_ADDRESS"
    echo "  TO   : $DESTINATION_ADDRESS"
    echo "------------------------------------------------------------"
    if terraform state mv -state="$TERRAFORM_PATH/terraform.tfstate" "$SOURCE_ADDRESS" "$DESTINATION_ADDRESS"; then
      echo "Resource moved successfully."
    else
      echo "ERROR: Failed to move resource. Check the addresses and try again."
      exit 1
    fi
    ;;

  remove)
    RESOURCE_ADDRESS="$2"
    TERRAFORM_PATH="$3"
    if [[ -z "$RESOURCE_ADDRESS" || -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide a resource address and Terraform path."
      usage
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "WARNING: This will remove '$RESOURCE_ADDRESS' from Terraform state."
    echo "The actual infrastructure resource will NOT be destroyed."
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
      echo "Aborted."
      exit 0
    fi
    echo "------------------------------------------------------------"
    if terraform state rm -state="$TERRAFORM_PATH/terraform.tfstate" "$RESOURCE_ADDRESS"; then
      echo "Resource '$RESOURCE_ADDRESS' removed from state."
    else
      echo "ERROR: Failed to remove resource. Check the address and try again."
      exit 1
    fi
    ;;

  pull)
    TERRAFORM_PATH="$2"
    if [[ -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide a Terraform path."
      usage
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "Pulling raw state for: $TERRAFORM_PATH"
    echo "------------------------------------------------------------"
    terraform state pull "$TERRAFORM_PATH"
    ;;

  *)
    echo "ERROR: Unknown command '$COMMAND'."
    usage
    ;;

esac

######################################################################################
