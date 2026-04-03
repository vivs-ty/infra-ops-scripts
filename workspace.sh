#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

# Usage help
usage() {
  echo ""
  echo "Terraform Workspace Manager"
  echo ""
  echo "SYNTAX  = ./workspace.sh <COMMAND> [WORKSPACE_NAME] <PATH>"
  echo ""
  echo "COMMANDS:"
  echo "  list    <PATH>                  - List all workspaces"
  echo "  show    <PATH>                  - Show the current active workspace"
  echo "  create  <WORKSPACE_NAME> <PATH> - Create a new workspace"
  echo "  select  <WORKSPACE_NAME> <PATH> - Switch to an existing workspace"
  echo "  delete  <WORKSPACE_NAME> <PATH> - Delete a workspace"
  echo ""
  echo "EXAMPLES:"
  echo "  ./workspace.sh list terraform/instance"
  echo "  ./workspace.sh show terraform/instance"
  echo "  ./workspace.sh create dev terraform/instance"
  echo "  ./workspace.sh select staging terraform/instance"
  echo "  ./workspace.sh delete dev terraform/instance"
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
    echo "Listing workspaces in: $TERRAFORM_PATH"
    terraform workspace list "$TERRAFORM_PATH"
    ;;

  show)
    TERRAFORM_PATH="$2"
    if [[ -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide a Terraform path."
      usage
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "Current workspace:"
    terraform workspace show "$TERRAFORM_PATH"
    ;;

  create)
    WORKSPACE_NAME="$2"
    TERRAFORM_PATH="$3"
    if [[ -z "$WORKSPACE_NAME" || -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide a workspace name and Terraform path."
      usage
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "Creating workspace: $WORKSPACE_NAME"
    if terraform workspace new "$WORKSPACE_NAME" "$TERRAFORM_PATH"; then
      echo "Workspace '$WORKSPACE_NAME' created and selected."
    else
      echo "ERROR: Failed to create workspace '$WORKSPACE_NAME'."
      exit 1
    fi
    ;;

  select)
    WORKSPACE_NAME="$2"
    TERRAFORM_PATH="$3"
    if [[ -z "$WORKSPACE_NAME" || -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide a workspace name and Terraform path."
      usage
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "Switching to workspace: $WORKSPACE_NAME"
    if terraform workspace select "$WORKSPACE_NAME" "$TERRAFORM_PATH"; then
      echo "Now on workspace: $WORKSPACE_NAME"
    else
      echo "ERROR: Workspace '$WORKSPACE_NAME' not found."
      echo "Run './workspace.sh list $TERRAFORM_PATH' to see available workspaces."
      exit 1
    fi
    ;;

  delete)
    WORKSPACE_NAME="$2"
    TERRAFORM_PATH="$3"
    if [[ -z "$WORKSPACE_NAME" || -z "$TERRAFORM_PATH" ]]; then
      echo "ERROR: Please provide a workspace name and Terraform path."
      usage
    fi
    if [[ "$WORKSPACE_NAME" == "default" ]]; then
      echo "ERROR: The 'default' workspace cannot be deleted."
      exit 1
    fi
    echo "Initializing Terraform..."
    terraform init "$TERRAFORM_PATH"
    echo ""
    echo "Deleting workspace: $WORKSPACE_NAME"
    if terraform workspace delete "$WORKSPACE_NAME" "$TERRAFORM_PATH"; then
      echo "Workspace '$WORKSPACE_NAME' deleted."
    else
      echo "ERROR: Failed to delete workspace '$WORKSPACE_NAME'."
      echo "Make sure you are not currently on that workspace before deleting."
      exit 1
    fi
    ;;

  *)
    echo "ERROR: Unknown command '$COMMAND'."
    usage
    ;;

esac

######################################################################################
