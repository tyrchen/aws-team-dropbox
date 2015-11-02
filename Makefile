PROFILE=$(AWSP) # if you want to use a different profile, set env variable AWSP=--profile <profile name>
OUTPUT_TEXT=--output text
OUTPUT_TABLE=--output table

# extract account id from current user ARN
ACCOUNT_ID=$(shell aws iam get-user $(PROFILE) | awk '/arn:aws:/{print $2}' | egrep -o '[0-9]+')

POLICY_FOLDER=policies
POLICY_PREFIX=it

USER_POLICY_FILES=$(shell find policies -name "user-*.json")
USER_POLICIES=$(USER_POLICY_FILES:$(POLICY_FOLDER)/%.json=$(POLICY_PREFIX)-%)
USER_POLICY_ARNS=$(USER_POLICY_FILES:$(POLICY_FOLDER)/%.json=policy/$(POLICY_PREFIX)-%)

RESOURCE_S3_PREFIX=resource-s3
RESOURCE_S3_POLICY_FILES=$(shell find policies -name "$(RESOURCE_S3_PREFIX)-*.json")
RESOURCE_S3_POLICIES=$(RESOURCE_S3_POLICY_FILES:$(POLICY_FOLDER)/$(RESOURCE_S3_PREFIX)-%.json=%)


GROUP_NAME=corp-user
INIT_PASS=hell0World

S3_TEAM_BUCKET=corp-fs-team-bucket
S3_WEB_BUCKET=corp-fs-web-bucket
S3_HOME_FOLDER=home
S3_DOC_FOLDER=eng/doc
S3_FOLDERS=$(S3_HOME_FOLDER) $(S3_DOC_FOLDER)
ASSET_FOLDER=assets
EMPTY_FILE=empty-file.txt


usage:
	@echo list of commands: create-group, create-user, create-policy, update-policy

## User creation related
create-user:
	@echo Creating user: $(username)...
	@aws iam create-user --user-name $(username) $(PROFILE)
	@echo Adding user to group $(GROUP_NAME)...
	@aws iam add-user-to-group --user-name $(username) --group-name $(GROUP_NAME) $(PROFILE)
	@echo Creating password...
	@aws iam create-login-profile --user-name $(username) --password $(INIT_PASS) $(PROFILE)
	@echo Creating access key...
	@aws iam create-access-key --user-name $(username) $(PROFILE)
	make init-user-folder username=$(username)

delete-user: delete-test-user delete-user-from-group delete-user-login-profile delete-user-access-key delete-user-home-folder
	@echo Deleting user: $(username)...
	@aws iam delete-user --user-name $(username) $(PROFILE)

delete-test-user:
	@while [ -z "$$CONTINUE" ]; do \
		read -r -p "Are you sure to delete user $(username)? [y/N]: " CONTINUE; \
	done ; \
	[ $$CONTINUE = "y" ] || [ $$CONTINUE = "Y" ] || (echo "Exiting."; exit 1;)

delete-user-from-group:
	@echo Removing user $(username) from group $(GROUP_NAME)...
	@aws iam remove-user-from-group --user-name $(username) --group-name $(GROUP_NAME) $(PROFILE)

delete-user-login-profile:
	@echo Deleting login profile for user $(username)...
	-@aws iam delete-login-profile --user-name $(username) $(PROFILE)

delete-user-access-key:
	@echo Deleting access key for user $(username)...
	$(eval KEYS:=$(shell aws iam list-access-keys --user-name $(username) $(PROFILE) $(OUTPUT_TEXT) | awk '{print $$2}'))
	$(foreach KEY, $(KEYS), aws iam delete-access-key --user-name $(username) --access-key-id $(KEY) $(PROFILE);)

delete-user-home-folder:
	@echo Deleting home folder...
	@aws s3 rm s3://$(S3_TEAM_BUCKET)/home/$(username) --recursive $(PROFILE)

init-user-folder:
	@echo Creating home folder...
	@$(foreach DIR, $(S3_FOLDERS), aws s3 cp $(ASSET_FOLDER)/$(EMPTY_FILE) s3://$(S3_TEAM_BUCKET)/$(DIR)/$(username)/$(EMPTY_FILE) $(PROFILE);)

create-group:
	@echo Creating group: $(GROUP_NAME)...
	-@aws iam create-group --group-name corp-user $(PROFILE)
	@echo Attaching policies: $(USER_POLICY_ARNS)...
	$(eval POLICY_ARN_PREFIX:=arn:aws:iam::$(ACCOUNT_ID))
	@$(foreach ARN, $(USER_POLICY_ARNS), aws iam attach-group-policy --group-name corp-user --policy-arn $(POLICY_ARN_PREFIX):$(ARN) $(PROFILE);)


## S3 bucket and folders initialization
init-s3: init-team-bucket init-web-bucket

init-team-bucket:
	@echo Creating bucket $(S3_TEAM_BUCKET)...
	-@aws s3 mb s3://$(S3_TEAM_BUCKET) $(PROFILE)
	@$(foreach DIR, $(S3_FOLDERS), aws s3 cp $(ASSET_FOLDER)/$(EMPTY_FILE) s3://$(S3_TEAM_BUCKET)/$(DIR)/$(EMPTY_FILE) $(PROFILE);)

init-web-bucket:
	@echo Creating bucket $(S3_WEB_BUCKET)...
	-@aws s3 mb s3://$(S3_WEB_BUCKET) $(PROFILE)
	-@make sync-web-bucket
	@echo Setting web hosting for the bucket...
	@aws s3 website s3://$(S3_WEB_BUCKET) --index-document index.html --error-document 404.html $(PROFILE)

sync-web-bucket:
	@echo uploading files to bucket $(S3_WEB_BUCKET)...
	@aws s3 sync s3website s3://$(S3_WEB_BUCKET) $(PROFILE)

## policy initialization
create-policy: $(USER_POLICIES) $(RESOURCE_S3_POLICIES)

update-policy: $(USER_POLICY_ARNS)

$(USER_POLICY_ARNS):policy/$(POLICY_PREFIX)-%:$(POLICY_FOLDER)/%.json
	$(eval POLICY_ARN_PREFIX:=arn:aws:iam::$(ACCOUNT_ID))
	@echo Updating policy $(POLICY_ARN_PREFIX):$@ with file $<
	@aws iam create-policy-version --policy-arn $(POLICY_ARN_PREFIX):$@ --policy-document file://$< --set-as-default $(PROFILE)

$(USER_POLICIES):$(POLICY_PREFIX)-%:$(POLICY_FOLDER)/%.json
	@echo Creating policy $@ with file $<
	-@aws iam create-policy --policy-name $@ --policy-document file://$< $(PROFILE)

$(RESOURCE_S3_POLICIES):$(RESOURCE_S3_PREFIX)-%:$(POLICY_FOLDER)/$(RESOURCE_S3_PREFIX)-%.json
	$(eval POLICY_FILE:=$(POLICY_FOLDER)/$(RESOURCE_S3_PREFIX)-$@.json)
	@echo Updating policy for S3 bucket $@ with file $(POLICY_FILE)
	@aws s3api put-bucket-policy --bucket $@ --policy file://$(POLICY_FILE) $(PROFILE)

## lambda initialization