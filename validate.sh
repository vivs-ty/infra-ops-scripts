#!/bin/bash

######################################################################################

# Export Path Variable
export PATH=$PATH:/opt

######################################################################################

# If statement to ensure a user has provided a Terraform folder path
if [[ -z "$1" ]]; then
  echo ""
  echo "You have not provided a Terraform path."
  echo "SYNTAX  = ./validate.sh <PATH>"
  echo "EXAMPLE = ./validate.sh terraform/instance"
  echo ""
  exit 1
fi

######################################################################################

# Initialize the working directory first (required before validate)
echo "Initializing Terraform..."
terraform init "$1"

######################################################################################

# Check that all Terraform files are formatted correctly
echo ""
echo "Running terraform fmt check..."
if ! terraform fmt -check -recursive "$1"; then
  echo ""
  echo "ERROR: Terraform files are not formatted correctly."
  echo "Run 'terraform fmt -recursive $1' to fix formatting."
  echo ""
  exit 1
fi
echo "Formatting check passed."

######################################################################################

# Validate the Terraform configuration for syntax and internal consistency
echo ""
echo "Running terraform validate..."
if ! terraform validate "$1"; then
  echo ""
  echo "ERROR: Terraform validation failed. Review the errors above."
  echo ""
  exit 1
fi
echo "Validation passed."

######################################################################################

echo ""
echo "All checks passed for: $1"
echo ""
