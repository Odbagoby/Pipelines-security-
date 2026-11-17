# Copy to terraform.tfvars (git-ignored) and edit.
aws_region        = "eu-central-1"
github_repository = "your-github-username/secure-pipeline-demo"

# Step 2, after the pipeline has pushed its first image:
# create_app_runner = true
# initial_image_tag = "<full commit SHA of that pipeline run>"
