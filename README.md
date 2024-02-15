# tf-gcp-infra

## GCP Networking Setup

1. VPC Network:
   - Disabled auto-create 
   - Regional routing mode
   - No default routes
2. Subnet #1: webapp
   - /24 CIDR range
3. Subnet #2: db
   - /24 CIDR range
4. Attached Internet Gateway to the VPC

## How to build & run the application

1. Clone this repository to your local machine.

2. Navigate to the directory containing the Terraform configuration files.

3. Update the `terraform.tfvars` file with your specific configurations:

   ```hcl
   service_account_file_path = "path/to/your/service-account-key.json"
   prj_id                    = "your-gcp-project-id"
   cloud_region              = "your-gcp-region"
   ```

4. Modify the VPC configurations in the `variables.tf` file as per your requirements:

5. Terraform Initalization
   
    ```
    terraform init
    ```

3. Terraform Validate
   
   ```
   terraform validate
   ```

4. Terraform Apply
   
   ```
   terraform apply
   ```

5. Cleanup
   To avoid incurring necessary charges, remember to destroy the Terraform-managed infrastructure when it's no longer needed
   
   ```
   terraform destroy
   ```

## Enabled GCP Service APIs

1. Compute Engine API
2. Cloud SQL Admin API
3. Cloud Storage JSON API
4. Cloud Logging API
5. Cloud Monitoring API
6. Identity and Access Management (IAM) API
7. Cloud DNS API
8. Cloud Build API

## References:

1. [Install Homebrew](https://brew.sh/): Homebrew is a package manager for macOS that simplifies the installation of various software packages.

2. [Install Terraform using Homebrew](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started): Once Homebrew is installed, you can use it to install Terraform with the following command:
   ```
   brew install terraform
   ```
3. [Set up Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started): Follow the official HashiCorp documentation to learn more about setting up Terraform on macOS.