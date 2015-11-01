PROFILE=$(AWSP) # if you want to use a different profile, set env variable AWSP=--profile <profile name>
ACCOUNT_ID:=$(shell aws iam get-user $(PROFILE) | awk '/arn:aws:/{print $2}' | egrep -o '[0-9]+')

POLICY_FOLDER=policies
POLICY_PREFIX=it-user
POLICY_FILES=$(shell find policies -name *.json)
POLICIES=$(POLICY_FILES:$(POLICY_FOLDER)/%.json=$(POLICY_PREFIX)-%)
POLICY_ARNS=$(POLICY_FILES:$(POLICY_FOLDER)/%.json=policy/$(POLICY_PREFIX)-%)
POLICY_ARN_PREFIX=arn:aws:iam::$(ACCOUNT_ID)

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

create-user:
	@echo Creating user: "$(username)"...
	@aws iam create-user --user-name $(username) $(PROFILE)
	@echo Adding user to group $(GROUP_NAME)...
	@aws iam add-user-to-group --user-name $(username) --group-name $(GROUP_NAME) $(PROFILE)
	@echo Creating password...
	@aws iam create-login-profile --user-name $(username) --password $(INIT_PASS) $(PROFILE)
	@echo Creating access key...
	@aws iam create-access-key --user-name $(username) $(PROFILE)
	make init-user-folder username=$(username)

init-user-folder:
	@echo Creating home folder...
	@$(foreach DIR, $(S3_FOLDERS), aws s3 cp $(ASSET_FOLDER)/$(EMPTY_FILE) s3://$(S3_TEAM_BUCKET)/$(DIR)/$(username)/$(EMPTY_FILE) $(PROFILE);)

create-group:
	@echo Creating group: $(GROUP_NAME)...
	-@aws iam create-group --group-name corp-user $(PROFILE)
	@$(foreach ARN, $(POLICY_ARNS), aws iam attach-group-policy --group-name corp-user --policy-arn $(POLICY_ARN_PREFIX):$(ARN) $(PROFILE);)


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

create-policy: $(POLICIES)

update-policy: $(POLICY_ARNS)

$(POLICY_ARNS):policy/$(POLICY_PREFIX)-%:$(POLICY_FOLDER)/%.json
	@echo Updating policy $@ with file $<
	@aws iam create-policy-version --policy-arn $(POLICY_ARN_PREFIX):$@ --policy-document file://$< --set-as-default $(PROFILE)

$(POLICIES):$(POLICY_PREFIX)-%:$(POLICY_FOLDER)/%.json
	@echo Creating policy $@ with file $<
	@aws iam create-policy --policy-name $@ --policy-document file://$< $(PROFILE)

