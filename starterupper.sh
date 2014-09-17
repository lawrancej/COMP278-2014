#!/bin/bash
# Starter Upper: Setup git hosting for classroom use with minimal user interaction.

# Configuration
# ---------------------------------------------------------------------

# The repository to clone as upstream (NO SPACES)
readonly REPO=COMP278-2014
# Domain for school email
readonly SCHOOL=wit.edu
# The instructor's Github username
readonly INSTRUCTOR_GITHUB=lawrancej

# Issues:
# Make all functions idempotent
# start / open a bookmarklet?
# go through all pages when fetching usernames
# grading interface: checkout stuff rapid fire like, possibly use git notes
# fall back to https remotes if the school doesn't support SSH
# if the public key already exists on another account, ask user if they'd like to wipe existing keypair and generate a new one.
# revoke authorization automatically DELETE /authorizations/:id  (need to store the id in the first place)
# bitbucket, gitlab support
# make it work for team projects
# make it work if the instructor repository is private (one way to achieve this would be to create the student private repo first)

# Runtime flags (DO NOT CHANGE)
# ---------------------------------------------------------------------
readonly PROGNAME=$(basename $0)
readonly ARGS="$@"

# Utilities
# ---------------------------------------------------------------------

# Cross-platform paste to clipboard
Utility_paste() {
    local text="$1"; shift
    local prompt="$1"
    case $OSTYPE in
        msys | cygwin ) echo "$text" > /dev/clipboard ;;
        linux* ) echo "$text" | xclip -selection clipboard ;;
        darwin* ) echo "$text" | pbcopy ;;
        *) printf "Please copy $prompt to the clipboard:\n$1\n"; return 0 ;;
    esac
    if [[ $OSTYPE == darwin* ]]; then
        printf "I copied $prompt to the clipboard. (Cmd-V or right click to paste)"
    else
        printf "I copied $prompt to the clipboard. (Ctrl-V or right click to paste)"
    fi
}

# Cross-platform file open
Utility_fileOpen() {
    case $OSTYPE in
        msys | cygwin ) echo "Opening $1"; start "$1" ;;
        linux* ) echo "Opening $1"; xdg-open "$1" ;;
        darwin* ) echo "Opening $1"; open "$1" ;;
        *) echo "Please open $1" ;;
    esac
}

# Validate nonempty value matches a regex
Utility_nonEmptyValueMatchesRegex() {
    local value="$1"; shift
    local regex="$1"
    
    # First, check if value is empty
    if [[ -z "$value" ]]; then
        printf "false"
    # Then, check whether value matches regex
    elif [[ -z $(echo "$value" | grep -E "$regex" ) ]]; then
        printf "false"
    else
        printf "true"
    fi
}

# Interactive functions
# ---------------------------------------------------------------------

# Cross platform file open
Interactive_fileOpen() {
    read < /dev/tty
    Utility_fileOpen "$1"
    read -p "Press enter to continue." < /dev/tty
    echo
}

# Ask the user to confirm whether the auto-detected value is correct.
Interactive_confirm() {
    local value="$1"; shift
    local validation="$1"; shift
    local prompt="$1";
    local yn='';
    # As long as we auto-guessed something that looks fine, ...
    while [[ "$("$validation" "$value")" == "true" ]]; do
        # Ask the user to confirm
        read -p "Is your $prompt $value (yes/no)? " yn < /dev/tty
        case "$yn" in
            # If the user's fine with it, we're done. Yay!
            [Yy] | [Yy][Ee][Ss] | "" ) return 0 ;;
            # If the user's not okay with it, we're done. Dang!
            [Nn] | [Nn][Oo] ) return 1 ;;
            # If the user's a goober, remind them what to do
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

# Ask the user to set the value
Interactive_setValue() {
    local key="$1"; shift
    local value="$1"; shift
    local validation="$1"; shift
    local prompt="$1"; shift
    local invalid="$1"; 
    
    # First, ask the user to confirm if the value we auto-guessed is correct
    Interactive_confirm "$value" "$validation" "$prompt"
    
    # If the user wasn't okay with the default value, ask for the right one.
    if [[ 1 -eq $? ]]; then
        # Well, clearly the user didn't like the value
        value=""
        # So, as long as the value is bogus, ...
        while [[ "$("$validation" "$value")" == "false" ]]; do
            # Ask for the right value
            read -p "Enter your $prompt: " value < /dev/tty
            # But, don't assume the user knows what they're doing
            if [[ "$("$validation" "$value")" == "false" ]]; then
                echo -e "\e[1;37;41mERROR\e[0m: '$value' is not a $prompt. $invalid"
            fi
        done
        # By now, the user entered something that is at least plausible
    fi
    
    # Finally, set the key
    git config --global $key "$value"
}

# User functions
# ---------------------------------------------------------------------

# Get the user's username
User_getUsername() {
    local username="$USERNAME"
    if [[ -z "$username" ]]; then
        username="$(id -nu 2> /dev/null)"
    fi
    if [[ -z "$username" ]]; then
        username="$(whoami 2> /dev/null)"
    fi
    printf "$username"
}

# A full name needs a first and last name
Valid_fullName() {
    local fullName="$1"
    printf "$(Utility_nonEmptyValueMatchesRegex "$fullName" "\w+ \w+")"
}

# Get the user's full name (Firstname Lastname); defaults to OS-supplied full name
# Side effect: set ~/.gitconfig user.name if unset and full name from OS validates.
User_getFullName() {
    # First, look in the git configuration
    local fullName="$(git config user.name)"
    
    # Ask the OS for the user's full name, if it's not valid
    if [[ "$(Valid_fullName "$fullName")" == "false" ]]; then
        local username="$(User_getUsername)"
        case $OSTYPE in
            msys | cygwin )
                cat << 'EOF' > getfullname.ps1
$MethodDefinition = @'
[DllImport("secur32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern int GetUserNameEx (int nameFormat, System.Text.StringBuilder userName, ref uint userNameSize);
'@
$windows = Add-Type -MemberDefinition $MethodDefinition -Name 'Secur32' -Namespace 'Win32' -PassThru
$sb = New-Object System.Text.StringBuilder
$num=[uint32]256
$windows::GetUserNameEx(3, $sb, [ref]$num) | out-null
$sb.ToString()
EOF
                fullName=$(powershell -executionpolicy remotesigned -File getfullname.ps1 | sed -e 's/\(.*\), \(.*\)/\2 \1/')
                rm getfullname.ps1 > /dev/null
                ;;
            linux* )
                fullName=$(getent passwd "$username" | cut -d ':' -f 5 | cut -d ',' -f 1)
                ;;
            darwin* )
                fullName=$(dscl . read /Users/`whoami` RealName | grep -v RealName | cut -c 2-)
                ;;
            *) fullName="" ;;
        esac
        
        # If we got a legit full name from the OS, update the git configuration to reflect it.
        if [[ "$(Valid_fullName "$fullName")" == "true" ]]; then
            git config --global user.name "$fullName"
        fi
    fi
    printf "$fullName"
}

# We're assuming that students have a .edu email address
Valid_email() {
    local email="$1"
    printf "$(Utility_nonEmptyValueMatchesRegex "$email" "edu$")"
}

# Get the user's email; defaults to username@school
# Side effect: set ~/.gitconfig user.email if unset
User_getEmail() {
    # Try to see if the user already stored the email address
    local email="$(git config user.email)"
    # If the stored email is bogus, ...
    if [[ "false" == $(Valid_email "$email") ]]; then
        # Guess an email address and save it
        email="$(User_getUsername)@$SCHOOL"
        git config --global user.email "$email"
    fi
    printf "$email"
}

# Interactively setup user information
User_setup() {
    Interactive_setValue "user.name" "$(User_getFullName)" "Valid_fullName" "full name" "Include your first and last name."
    Interactive_setValue "user.email" "$(User_getEmail)" "Valid_email" "school email address" "Use your .edu address."
}

# SSH
# ---------------------------------------------------------------------

# Get the user's public key
SSH_getPublicKey() {
    # If the public/private keypair doesn't exist, make it.
    if ! [[ -f ~/.ssh/id_rsa.pub ]]; then
        # Use default location, set no phassphrase, no questions asked
        printf "\n" | ssh-keygen -t rsa -N '' 2> /dev/null > /dev/null
    fi
    cat ~/.ssh/id_rsa.pub
}

# Test connection
SSH_connected() {
    local hostDomain="$1"; shift
    local sshTest=$(ssh -oStrictHostKeyChecking=no git@$hostDomain 2>&1)
    if [[ 255 -eq $? ]]; then
        printf "false"
    else
        printf "true"
    fi
}

# Git
# ---------------------------------------------------------------------

# Clone repository and configure remotes
Git_configureRepository() {
    local hostDomain="$1"
    local originLogin="$2"
    local upstreamLogin="$3"
    local origin="git@$hostDomain:$originLogin/$REPO.git"
    local upstream="https://$hostDomain/$upstreamLogin/$REPO.git"
    
    # It'll go into the user's home directory
    cd ~
    if [ ! -d $REPO ]; then
        git clone "$upstream"
    fi

    # Configure remotes
    cd ~/$REPO
    git remote rm origin 2> /dev/null
    git remote rm upstream 2> /dev/null
    git remote add origin "$origin"
    git remote add upstream "$upstream"
    git config branch.master.remote origin
    git config branch.master.merge refs/heads/master
}

# Show the local and remote repositories
Git_showRepositories() {
    local remote="$(git remote -v | grep origin | sed -e 's/.*git@\(.*\):\(.*\)\/\(.*\)\.git.*/https:\/\/\1\/\2\/\3/' | head -n 1)"
    cd ~
    # Open local repository in file browser
    Utility_fileOpen $REPO
    # Open remote repository in web browser
    Utility_fileOpen "$remote"
}

# Push repository, and show the user local/remote repositories
# Preconditions:
# 1. SSH public/private keypair was generated
# 2. The project host username was properly set
# 3. SSH public key was shared with host
# 4. SSH is working
# 5. The private repo exists
Git_pushRepo() {
    cd ~/$REPO
    git push -u origin master # 2> /dev/null
    local result=$(echo $?)
    if [[ $result != 0 ]]; then
        echo -e "\e[1;37;41mERROR\e[0m: Unable to push."
        echo "Failed."
    else
        Git_showRepositories
        echo "Done"
    fi
}

# Deprecated
# ---------------------------------------------------------------------

ssh_works=true # unless proven otherwise...

# Generic project host configuration functions
# ---------------------------------------------------------------------

# Get the project host username; defaults to machine username
Host_getUsername() {
    local host="$1"
    local username="$(git config $host.login)"
    if [[ -z "$username" ]]; then
        username="$(User_getUsername)"
    fi
    printf "$username"
}

# Github
# ---------------------------------------------------------------------

# Is the name available on Github?
Github_nameAvailable() {
    local username="$1"
    local result="$(curl -i https://api.github.com/users/$username 2> /dev/null)"
    if [[ -z $(echo $result | grep "HTTP/1.1 200 OK") ]]; then
        echo "true";
    else
        echo "false";
    fi
}

# A valid Github username is not available, by definition
Github_validUsername() {
    local username="$1"
    # If the name is legit, ...
    if [[ "$(Utility_nonEmptyValueMatchesRegex "$username" "^[0-9a-zA-Z][0-9a-zA-Z-]*$")" == "true" ]]; then
        # And unavailable, ...
        if [[ "$(Github_nameAvailable $username)" == "false" ]]; then
            # It's valid
            printf "true"
            return 0
        fi
    fi
    # Otherwise, it's not valid
    printf "false"
}

# Ask user to verify email
Github_verifyEmail() {
    echo "Press enter to open https://github.com/settings/emails to add your school email address."
    echo "Open your email inbox and wait a minute for an email from Github."
    echo "Follow its instructions: click the link in the email and click Confirm."
    echo "$(Utility_paste $(User_getEmail) "your school email")"
    Interactive_fileOpen "https://github.com/settings/emails"
}

# Ask the user to get the discount
Github_getDiscount() {
    echo "Press enter to open https://education.github.com/discount_requests/new to request an individual student educational discount from Github."
    Interactive_fileOpen "https://education.github.com/discount_requests/new"
}

# Ask the user if they have an account yet, and guide them through onboarding
Github_join() {
    local hasAccount="n"
    
    # If we don't have their github login, ...
    if [[ -z "$(git config --global github.login)" ]]; then
        # Ask if they're on github yet
        read -p "Do you have a Github account (yes or No [default])? " hasAccount < /dev/tty

        echo -e "\e[1;37;41mIMPORTANT\e[0m: Before we proceed, you need to complete ALL of these steps:"

        # Let's assume that they don't by default
        if [[ $hasAccount != [Yy]* ]]; then
            echo "1. Join Github, using $(User_getEmail) as your email address."
            echo "2. Open your email inbox and verify your school email address."
            echo "3. Request an individual student educational discount."
            echo ""
            
            echo "Press enter to join Github."
            Interactive_fileOpen "https://github.com/join"
        else
            echo "1. Share and verify your school email address with Github."
            echo "2. Request an individual student educational discount."
            echo ""
        fi
        
        Github_verifyEmail
        Github_getDiscount

    fi
}

# Set the Github username, if not already set
Github_setUsername() {
    Github_join
    if [[ -z "$(git config --global github.token)" ]]; then
        Interactive_setValue "github.login" "$(Host_getUsername "github")" "Github_validUsername" "Github username" "\nNOTE: Usernames are case-sensitive. See: https://github.com"
    fi
}

# Acquire authentication token and store in github.token
Github_authenticate() {
    # Don't bother if we already got the authentication token
    if [[ -n "$(git config --global github.token)" ]]; then
        return 0
    fi
    local token="HTTP/1.1 401 Unauthorized"
    local code=''
    local password=''
    local json=''
    # As long as we're unauthorized, ...
    while [[ ! -z "$(echo $token | grep "HTTP/1.1 401 Unauthorized" )" ]]; do
        # Ask for a password
        if [[ -z "$password" ]]; then
            read -s -p "Enter Github password (not shown or saved): " password < /dev/tty
            echo # We need this, otherwise it'll look bad
        fi
        # Generate authentication token request
        read -r -d '' json <<-EOF
            {
                "scopes": ["repo", "public_repo", "user", "write:public_key", "user:email"],
                "note": "starterupper $(date --iso-8601=seconds)"
            }
EOF
        token=$(curl -i -u $(Host_getUsername "github"):$password -H "X-GitHub-OTP: $code" -d "$json" https://api.github.com/authorizations 2> /dev/null)
        # If we got a bad credential, we need to reset the password and try again
        if [[ ! -z $(echo $token | grep "Bad credential") ]]; then
            echo -e "\e[1;37;41mERROR\e[0m: Incorrect password. Please wait a moment."
            password=''
            sleep 3
        fi
        # If the user has two-factor authentication, ask for it.
        if [[ ! -z $(echo $token | grep "two-factor" ) ]]; then
            read -p "Enter Github two-factor authentication code: " code < /dev/tty
        fi
    done
    # By now, we're authenticated, ...
    if [[ ! -z $(echo $token | grep "HTTP/... 20." ) ]]; then
        # So, extract the token and store it in github.token
        token=$(echo $token | tr '"' '\n' | grep -E '[0-9a-f]{40}')
        git config --global github.token "$token"
        echo "Authenticated!"
    # Or something really bad happened, in which case, github.token will remain unset...
    else
        # When bad things happen, degrade gracefully.
        echo -n -e "\e[1;37;41mERROR\e[0m: "
        echo "$token" | grep "HTTP/..."
        echo
        echo "I encountered a problem and need your help to finish these setup steps:"
        echo
        echo "1. Update your Github profile to include your full name."
        echo "2. Create private repository $REPO on Github."
        echo "3. Add $INSTRUCTOR_GITHUB as a collaborator."
        echo "4. Share your public SSH key with Github."
        echo "5. Push to your private repository."
        echo
    fi
}

# Invoke a Github API method requiring authorization using curl
Github_invoke() {
    local method=$1; shift
    local url=$1; shift
    local data=$1;
    local header="Authorization: token $(git config --global github.token)"
    curl -i --request "$method" -H "$header" -d "$data" "https://api.github.com$url" 2> /dev/null
}

# Share full name with Github
Github_setFullName() {
    local fullName="$(User_getFullName)"
    # If authentication failed, degrade gracefully
    if [[ -z $(git config --global github.token) ]]; then
        echo "Press enter to open https://github.com/settings/profile to update your Github profile."
        echo "On that page, enter your full name. $(Utility_paste "$fullName" "your full name")"
        echo "Then, click Update profile."
        Interactive_fileOpen "https://github.com/settings/profile"
    # Otherwise, use the API
    else
        echo "Updating Github profile information..."
        Github_invoke PATCH "/user" "{\"name\": \"$fullName\"}" > /dev/null
    fi
}

# Share the public key
Github_sharePublicKey() {
    local githubLogin="$(Host_getUsername "github")"
    # If authentication failed, degrade gracefully
    if [[ -z "$(git config --global github.token)" ]]; then
        echo "Press enter to open https://github.com/settings/ssh to share your public SSH key with Github."
        echo "On that page, click Add SSH Key, then enter these details:"
        echo "Title: $(hostname)"
        echo "Key: $(Utility_paste "$(SSH_getPublicKey)" "your public SSH key")"
        Interactive_fileOpen "https://github.com/settings/ssh"
    # Otherwise, use the API
    else
        # Check if public key is shared
        local publickeyShared=$(curl -i https://api.github.com/users/$githubLogin/keys 2> /dev/null)
        # If not shared, share it
        if [[ -z $(echo "$publickeyShared" | grep $(SSH_getPublicKey | sed -e 's/ssh-rsa \(.*\)=.*/\1/')) ]]; then
            echo "Sharing public key..."
            Github_invoke POST "/user/keys" "{\"title\": \"$(hostname)\", \"key\": \"$(SSH_getPublicKey)\"}" > /dev/null
        fi
    fi
    # Test SSH connection on default port (22)
    if [[ "$(SSH_connected "github.com")" == "false" ]]; then
        echo "Your network has blocked port 22; trying port 443..."
        printf "Host github.com\n  Hostname ssh.github.com\n  Port 443\n" >> ~/.ssh/config
        # Test SSH connection on port 443
        if [[ "$(SSH_connected "github.com")" == "false" ]]; then
            echo "WARNING: Your network has blocked SSH."
            ssh_works=false
        fi
    fi
}

# Create a private repository manually
Github_manualCreatePrivateRepo() {
    echo "Press enter to open https://github.com/new to create private repository $REPO on Github."
    echo "On that page, for Repository name, enter: $REPO. $(Utility_paste "$REPO" "the repository name")"
    echo "Then, select Private and click Create Repository (DON'T tinker with other settings)."
    Interactive_fileOpen "https://github.com/new"
}

# Create a private repository on Github
Github_createPrivateRepo() {
    # If authentication failed, degrade gracefully
    if [[ -z "$(git config --global github.token)" ]]; then
        Github_manualCreatePrivateRepo
        return 0
    fi
    
    local githubLogin="$(Host_getUsername "github")"
    # Don't create a private repo if it already exists
    if [[ -z $(Github_invoke GET "/repos/$githubLogin/$REPO" "" | grep "Not Found") ]]; then
        return 0
    fi
    
    echo "Creating private repository $githubLogin/$REPO on Github..."
    local result="$(Github_invoke POST "/user/repos" "{\"name\": \"$REPO\", \"private\": true}")"
    if [[ ! -z $(echo $result | grep "HTTP/... 4.." ) ]]; then
        echo -n -e "\e[1;37;41mERROR\e[0m: "
        echo "Unable to create private repository."
        echo
        echo "Troubleshooting:"
        echo "* Make sure you have verified your school email address."
        echo "* Apply for the individual student educational discount if you haven't already done so."
        echo "* If you were already a Github user, free up some private repositories."
        echo
        
        Github_verifyEmail
        Github_getDiscount
        
        Github_manualCreatePrivateRepo
    fi
}

# Add a collaborator
Github_addCollaborator() {
    local githubLogin="$(Host_getUsername "github")"
    # If authentication failed, degrade gracefully
    if [[ -z "$(git config --global github.token)" ]]; then
        echo "Press enter to open https://github.com/$githubLogin/$REPO/settings/collaboration to add $1 as a collaborator."
        echo "$(Utility_paste "$1" "$1")"
        echo "Click Add collaborator."
        Interactive_fileOpen "https://github.com/$githubLogin/$REPO/settings/collaboration"
    # Otherwise, use the API
    else
        echo "Adding $1 as a collaborator..."
        Github_invoke PUT "/repos/$githubLogin/$REPO/collaborators/$1" "" > /dev/null
    fi
}

# Clean up everything but the repo (BEWARE!)
Github_clean() {
    echo "Delete starterupper-script under Personal access tokens"
    Interactive_fileOpen "https://github.com/settings/applications"
    sed -i s/.*github.com.*// ~/.ssh/known_hosts
    git config --global --unset user.name
    git config --global --unset user.email
    git config --global --unset github.login
    git config --global --unset github.token
    rm -f ~/.ssh/id_rsa*
}

# Test suite
# ---------------------------------------------------------------------

Test() {
    username=$(User_getUsername)
    fullname=$(User_getFullName)
    email=$(User_getEmail)
    echo $fullname
    echo $username
    echo $email

    verified=$(Utility_nonEmptyValueMatchesRegex "$fullname" "")

    public_key=$(SSH_getPublicKey)
    echo $public_key
    connected=$(SSH_connected "github.com")
    echo "SSH connected: $connected"
    connected=$(SSH_connected "bitbucket.org")
    echo "SSH connected: $connected"
    connected=$(SSH_connected "gitlab.com")
    echo "SSH connected: $connected"
    # Git_showRepositories
    echo "$(Github_nameAvailable $(Host_getUsername "github"))"
    echo "$(Github_nameAvailable "asdlfkjawer2")"
}

# Github functions
# ---------------------------------------------------------------------

# Setup a verified .edu email on github
github_configure_email() {

    # check if email is validated via api
    emails=$(curl -H "Authorization: token $(git config --global github.token)" https://api.github.com/user/emails 2> /dev/null | tr '\n}[]{' ' \n   ')

    # add email to github via api, if not set (e.g., for existing users registered with a different email) (FIXME: doesn't work)
    if [[ -z $(echo "$emails" | grep "$email") ]]; then
        curl -H "Authorization: token $(git config --global github.token)" -d "\"$email\"" https://api.github.com/user/emails  2> /dev/null > /dev/null
    fi
    # ask user to validate email if not validated
    if [[ -z $(echo "$emails" | grep "verified...true") ]]; then
        echo "IMPORTANT: Open your inbox and verify $email with Github."
        sleep 3
        file_open "https://github.com/settings/emails"
    else
        return 0
    fi
    # Nag the user until they get it right
    while [[ -z $(curl -H "Authorization: token $(git config --global github.token)" https://api.github.com/user/emails 2> /dev/null | tr '\n}[]{' ' \n   ' | grep "verified...true") ]]; do
        read -p "ERROR: $email is not verified yet. Verify, then press enter to continue." < /dev/tty
    done
}


Github_addCollaborators() {
    cd ~/$REPO
    for repository in $(Github_invoke GET "/user/repos?type=member\&sort=created\&page=1\&per_page=100" "" | grep "full_name.*$REPO" | sed s/.*full_name....// | sed s/..$//); do
        git remote add ${repository%/*} git@github.com:$repository.git 2> /dev/null
    done
    git fetch --all
}

github_user() {
    curl -i https://api.github.com/users/$1 2> /dev/null
}

gitlab_configure() {
    local_setup
    echo "Join GitLab."
    sleep 2
    file_open "https://gitlab.com/users/sign_up"
}

gitlab_authenticate() {
    if [[ -n "$(git config --global gitlab.token)" ]]; then
        return 0
    fi

    echo "Copy your private token from GitLab"
    sleep 2
    file_open "https://gitlab.com/profile/account"
    
    read -p "Paste your private token here: " token < /dev/tty
    
    while [[ ! -z "$(curl https://gitlab.com/api/v3/user?private_token=$token | grep '401 Unauthorized')" ]]; do
        echo "ERROR: Invalid private token."
        read -p "Paste your private token here: " token < /dev/tty    
    done
    git config --global gitlab.token "$token"
}

gitlab_setup_ssh() {
    gitlab_authenticate
    
    # Check if public key is shared
    publickey_shared=$(curl https://gitlab.com/api/v3/user/keys?private_token=$(git config --global gitlab.token) 2> /dev/null | grep $(cat ~/.ssh/id_rsa.pub | sed -e 's/ssh-rsa \(.*\)=.*/\1/'))
    # If not, share it
    if [[ -z "$publickey_shared" ]]; then
        echo "Sharing public key..."
        curl -i -H -d "{\"title\": \"$(hostname)\", \"key\": \"$(cat ~/.ssh/id_rsa.pub)\"}" https://api.github.com/user/keys?private_token=$(git config --global gitlab.token) 2> /dev/null > /dev/null
    fi
}

Gravatar_setup() {
    echo "Press enter to sign up to create a Gravatar (profile picture)."
    echo "$(Utility_paste "$(User_getEmail)" "your school email address")"
    Interactive_fileOpen "https://en.gravatar.com/connect/"
}

if [ $# == 0 ]; then
    User_setup
    Gravatar_setup
    Github_setUsername
    Git_configureRepository "github.com" "$(Host_getUsername "github")" "$INSTRUCTOR_GITHUB"
    Github_authenticate
    Github_setFullName
    Github_createPrivateRepo
    Github_addCollaborator $INSTRUCTOR_GITHUB
    Github_sharePublicKey
    Git_pushRepo
elif [[ $1 == "clean" ]]; then
    Github_clean
elif [[ $1 == "collaborators" ]]; then
    Github_addCollaborators
fi
