#!/bin/bash
# Starter Upper: Setup git hosting for classroom use with minimal user interaction.

# Configuration
# ---------------------------------------------------------------------

# School domain to use in email address example
readonly SCHOOL=wit.edu
# The instructor's name
readonly INSTRUCTOR_NAME="Joey Lawrance"
# The instructor's email
readonly INSTRUCTOR_EMAIL="lawrancej@wit.edu"
# The instructor's Github username
readonly INSTRUCTOR_GITHUB=lawrancej
# The repository to clone as upstream (NO SPACES)
readonly REPO=COMP278-2014

# Issues:
# Its like it knows their name, but doesn't really
# sniffing for educational discount is still broken
# unprocessable entities even without ssh keys being sent?!?
# Figure out if it's going to education.github.com
# SSH CONFIG PROBLEM : check if you overwrite .ssh/config
# REPOS NOT SHOWING UP: need to go to education.github.com and figure out how to verify it
# SETUP LOCAL FIRST
# Make all functions idempotent
# Resubmitting keys won't work (already exists) unprocessable entitites
# start / open a bookmarklet?
# go through all pages when fetching usernames
# grading interface: checkout stuff rapid fire like, possibly use git notes
# fall back to https remotes if the school doesn't support SSH
# if the public key already exists on another account, ask user if they'd like to wipe existing keypair and generate a new one.
# revoke authorization automatically DELETE /authorizations/:id  (need to store the id in the first place)
# use github user's full name in camel case as remote name when doing collaborator setup
# bitbucket, gitlab support
# make it work for team projects
# make it work if the instructor repository is private (one way to achieve this would be to create the student private repo first)
# technically, it's not necessary to store the github username.
# go with default if the user presses enter

# Runtime flags (DO NOT CHANGE)
# ---------------------------------------------------------------------
readonly PROGNAME=$(basename $0)
readonly ARGS="$@"

ssh_works=true # unless proven otherwise...
fullname=''
email=''
github_login=''

# Utilities
# ---------------------------------------------------------------------

# Return whether the string is empty
is_empty() {
    local var=$1
    [[ -z $var ]]
}

# Set $USERNAME, if not already set.
set_username() {
    is_empty "$USERNAME" && \
        USERNAME="$(id -nu 2> /dev/null)"

    is_empty "$USERNAME" && \
        USERNAME="$(whoami 2> /dev/null)"
}

# Get the user's full name
get_userfullname() {
    set_username

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
            FULLNAME=$(powershell -executionpolicy remotesigned -File getfullname.ps1 | sed -e 's/\(.*\), \(.*\)/\2 \1/')
            rm getfullname.ps1 > /dev/null
            ;;
        linux* )
            FULLNAME=$(getent passwd "$USERNAME" | cut -d ':' -f 5 | cut -d ',' -f 1)
            ;;
        darwin* )
            FULLNAME=$(dscl . read /Users/`whoami` RealName | grep -v RealName | cut -c 2-)
            ;;
        *) FULLNAME="" ;;
    esac
    if [[ -z "$FULLNAME" ]]; then
        FULLNAME="Jane Smith"
    fi
}

next_step() {
    read -p "Press enter to continue." < /dev/tty
}

# Cross platform file open
file_open() {
    case $OSTYPE in
        msys | cygwin ) echo "Opening $1"; sleep 1; start "$1" ;;
        linux* ) echo "Opening $1"; sleep 1; gnome-open "$1" ;;
        darwin* ) echo "Opening $1"; sleep 1; open "$1" ;;
        *) echo "Please open $1" ;;
    esac
    next_step
}

# Local functions
# ---------------------------------------------------------------------

instructor_setup() {
    user_is_instructor=true
    git config --global user.name "$INSTRUCTOR_NAME"
    fullname="$INSTRUCTOR_NAME"
    git config --global user.email "$INSTRUCTOR_EMAIL"
    email="$INSTRUCTOR_EMAIL"
    git config --global github.login "$INSTRUCTOR_GITHUB"
    github_login="$INSTRUCTOR_GITHUB"
}

# Ask the user if they are the instructor (by default, assume that they aren't)
instructor_check() {
    if [[ $user_is_instructor ]]; then
        return 0
    fi
    while ! [[ -z "$value" ]] && [[ "$value" == "$instructor" ]]; do
        read -p "Are you the instructor (yes/no)? " user_is_instructor < /dev/tty
        case "$user_is_instructor" in
            [Yy] | [Yy][Ee][Ss] ) instructor_setup; return 0 ;;
            [Nn] | [Nn][Oo] ) user_is_instructor=false; git config --global --unset $key; value=''; return 0 ;;
            "" ) user_is_instructor=false; git config --global --unset $key; value=''; return 0 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

# Check if the user is the instructor or complain if their value doesn't match the regex.
validate_input() {
    instructor_check
    
    if ! [[ -z "$value" ]] && [[ -z $(echo "$value" | grep -E "$validation_regex" ) ]]; then
        echo "ERROR: '$value' is not a $prompt. $invalid_prompt"
    fi
}

# Ask the user if they want to change their configuration in case of goof-ups (by default, assume that they don't)
change_config() {
    # If we already set a value before, don't bother changing the config again
    if [[ -n "$given_value" ]]; then
        return 0
    fi
    # Ask if the user is okay with what they set
    while ! [[ -z "$value" ]]; do
        read -p "Is your $prompt $value (yes/no)? " yn < /dev/tty
        case "$yn" in
            [Yy] | [Yy][Ee][Ss] ) return 0 ;;
            [Nn] | [Nn][Oo] ) git config --global --unset $key; value=''; return 0 ;;
            "" ) return 0 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

# Ask user to set a key in ~/.gitconfig if it's not already set.
# Sets $value only after the user's input passes $validation_regex
set_key() {
    key=$1
    prompt=$2
    example=$3
    validation_regex=$4
    invalid_prompt=$5
    instructor=$6
    given_value=$7
    
    value=$(git config --global $key)

    change_config
    validate_input
    while [[ -z "$value" ]] || [[ -z $(echo "$value" | grep -E "$validation_regex" ) ]]; do
        read -p "Enter your $prompt (e.g., $example): " value < /dev/tty
        validate_input
    done
    git config --global $key "$value"
}

# Generate SSH public/private keypair, if it doesn't already exist.
generate_ssh_keypair() {
    if [[ -f ~/.ssh/id_rsa.pub ]]; then
        return 0
    fi
    
    echo "Generating SSH public/private keypair..."
    # Use default location, set no phassphrase, no questions asked
    printf "\n" | ssh-keygen -t rsa -N '' 2> /dev/null > /dev/null
}

# Setup remotes for repository
# $1 is the SSH origin URL
# $2 is the HTTPS upstream URL
configure_remotes() {
    cd ~/$REPO
    echo "Configuring remotes..."
    # We remove and add again, in case the user goofed up before
    git remote rm origin 2> /dev/null
    git remote rm upstream 2> /dev/null
    git remote add origin $1
    git remote add upstream $2
    git config branch.master.remote origin
    git config branch.master.merge refs/heads/master
    cd ~
}

# Setup git user.name, user.email and ssh keypair.
# Sets: $fullname, $email, $USERNAME, $ssh_works
local_setup() {
    get_userfullname
    generate_ssh_keypair
    set_key user.name "full name" "$FULLNAME" "\w+ \w+" "Include your first and last name." "$INSTRUCTOR_NAME" "$fullname"
    fullname="$value"
    set_key user.email "school email address" "$USERNAME@$SCHOOL" "edu$" "Use your .edu address." "$INSTRUCTOR_EMAIL" "$email"
    email="$value"
}

# Github functions
# ---------------------------------------------------------------------

github_request_discount() {
    echo "Request an individual student discount from Github."
    sleep 2
    file_open "https://education.github.com/discount_requests/new"
}

# Asks user to login to github after joining
# Sets $github_login
github_configure() {
    local_setup
    
    # Ask if they've got a github account
    if [ -z $(git config --global github.login) ]; then
        read -p "Do you have a Github account (yes or No [default])? " has_github_account < /dev/tty
        # Let's assume that they don't by default
        if [[ $has_github_account != [Yy]* ]]; then
            echo "Join Github. IMPORTANT: Use $email as your email address."
            sleep 2
            file_open "https://github.com/join"
            echo "Open your inbox and verify your email with Github."
            sleep 2
            next_step
            github_request_discount
        fi
    fi
    if [[ -z $(git config --global github.token) ]]; then
        set_key github.login "Github username" "$USERNAME" "^[0-9a-zA-Z][0-9a-zA-Z-]*$" "See: https://github.com" "$INSTRUCTOR_GITHUB" "$github_login"
        # determine if username is found via api as a last minute sanity check
        while [[ -z $(github_user "$(git config --global github.login)" | grep "HTTP/... 20.") ]]; do
            echo "ERROR: username $(git config --global github.login) does not exist on Github."
            git config --global --unset github.login
            set_key github.login "Github username" "$USERNAME" "^[0-9a-zA-Z][0-9a-zA-Z-]*$" "See: https://github.com" "$INSTRUCTOR_GITHUB" "$github_login"
        done
    fi
    github_login=$(git config --global github.login)
}

# Wow, it's complicated
# https://github.com/sessions/forgot_password
# Sets github.token with authentication token
github_authenticate() {
    github_configure

    if [[ -n "$(git config --global github.token)" ]]; then
        return 0
    fi
    token="HTTP/1.1 401 Unauthorized"
    code=''
    password=''
    while [[ ! -z "$(echo $token | grep "HTTP/1.1 401 Unauthorized" )" ]]; do
        if [[ -z "$password" ]]; then
            read -s -p "Enter Github password: " password < /dev/tty
        fi
        token=$(curl -i -u $github_login:$password -H "X-GitHub-OTP: $code" -d '{"scopes": ["repo", "public_repo", "user", "write:public_key", "user:email"], "note": "starterupper-script"}' https://api.github.com/authorizations 2> /dev/null)
        echo
        if [[ ! -z $(echo $token | grep "Bad credential") ]]; then
            echo "Incorrect password. Please wait a moment."
            password=''
            sleep 3
        fi
        if [[ ! -z $(echo $token | grep "two-factor" ) ]]; then
            read -p "Enter Github two-factor authentication code: " code < /dev/tty
        fi
    done
    if [[ ! -z $(echo $token | grep "HTTP/... 20." ) ]]; then
        # Extract token and store it in github.token
        token=$(echo $token | tr '"' '\n' | grep -E '[0-9a-f]{40}')
        git config --global github.token "$token"
        echo "Authenticated!"
    else
        printf "Error: "
        echo "$token" | grep "HTTP/..." # Probably the user manually removed the token
        echo "Sorry, try again later."
        exit 1
    fi
}

github_set_name() {
    github_authenticate

    echo "Updating Github profile information..."
    curl --request PATCH -H "Authorization: token $(git config --global github.token)" -d "{\"name\": \"$(git config --global user.name)\"}" https://api.github.com/user 2> /dev/null > /dev/null
}

# Share the public key
github_setup_ssh() {
    github_authenticate

    # Check if public key is shared
    publickey_shared=$(curl -i https://api.github.com/users/$github_login/keys 2> /dev/null)
    # If not, share it
    if [[ -z $(echo "$publickey_shared" | grep $(cat ~/.ssh/id_rsa.pub | sed -e 's/ssh-rsa \(.*\)=.*/\1/')) ]]; then
        echo "Sharing public key..."
        curl -i -H "Authorization: token $(git config --global github.token)" -d "{\"title\": \"$(hostname)\", \"key\": \"$(cat ~/.ssh/id_rsa.pub)\"}" https://api.github.com/user/keys 2> /dev/null > /dev/null
    fi
    # Test SSH connection on default port (22)
    ssh_test=$(ssh -oStrictHostKeyChecking=no git@github.com 2>&1)
    if [[ -z $(echo $ssh_test | grep $github_login) ]]; then
        echo "Your network has blocked port 22; trying port 443..."
        printf "Host github.com\n  Hostname ssh.github.com\n  Port 443" >> ~/.ssh/config
        # Test SSH connection on port 443
        ssh_test=$(ssh -oStrictHostKeyChecking=no git@github.com 2>&1)
        if [[ -z $(echo $ssh_test | grep $github_login) ]]; then
            echo "WARNING: Your network has blocked SSH."
            ssh_works=false
        fi
    fi
}

# Setup a verified .edu email on github
github_configure_email() {
    github_authenticate

    # check if email is validated via api
    emails=$(curl -H "Authorization: token $(git config --global github.token)" https://api.github.com/user/emails 2> /dev/null | tr '\n}[]{' ' \n   ')

    # add email to github via api, if not set (e.g., for existing users registered with a different email)
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

github_create_private_repo() {
    github_setup_ssh
    github_configure_email
    
    # Don't create a private repo if it already exists
    if [[ -z $(curl -H "Authorization: token $(git config --global github.token)" https://api.github.com/repos/$github_login/$REPO 2> /dev/null | grep "Not Found") ]]; then
        return 0
    fi
    
    echo "Creating private repository $github_login/$REPO on Github..."
    result=$(curl -H "Authorization: token $(git config --global github.token)" -d "{\"name\": \"$REPO\", \"private\": true}" https://api.github.com/user/repos 2> /dev/null)
    if [[ ! -z $(echo $result | grep "over your quota" ) ]]; then
        echo "Unable to create private repository."
        github_request_discount
        result=$(curl -H "Authorization: token $(git config --global github.token)" -d "{\"name\": \"$REPO\", \"private\": true}" https://api.github.com/user/repos 2> /dev/null)
        if [[ ! -z $(echo $result | grep "over your quota" ) ]]; then
            echo "Unable to create private repository because you are over quota."
            echo "Wait for the discount and try again."
            if [[ $has_github_account == [Yy]* ]]; then
                echo "You may need to free up some private repositories."
                sleep 1
                file_open "https://github.com/settings/repositories"
            fi
            echo "Failed"
            exit 1
        fi
    fi
}

github_add_collaborator() {
    echo "Adding $1 as a collaborator..."
    curl --request PUT -H "Authorization: token $(git config --global github.token)" -d "" https://api.github.com/repos/$github_login/$REPO/collaborators/$1 2> /dev/null > /dev/null
}

github_add_collaborators() {
    cd ~/$REPO
    for repository in $(curl -i -H "Authorization: token $(git config --global github.token)" https://api.github.com/user/repos?type=member\&sort=created\&page=1\&per_page=100 2> /dev/null | grep "full_name.*$REPO" | sed s/.*full_name....// | sed s/..$//); do
        git remote add ${repository%/*} git@github.com:$repository.git 2> /dev/null
    done
    git fetch --all
}

github_user() {
    curl -i https://api.github.com/users/$1 2> /dev/null
}

github_setup() {
    github_set_name
    github_create_private_repo
    github_add_collaborator $INSTRUCTOR_GITHUB
    setup_repo
}

setup_repo() {
    cd ~
    origin="git@github.com:$github_login/$REPO.git"
    upstream="https://github.com/$INSTRUCTOR_GITHUB/$REPO.git"
    if [ ! -d $REPO ]; then
        git clone "$upstream"
    fi
    configure_remotes "$origin" "$upstream"
    file_open $REPO
    cd $REPO
    git push origin master # 2> /dev/null
    result=$(echo $?)
    if [[ $result != 0 ]]; then
        echo "ERROR: Unable to push."
        echo "Failed."
    else
        file_open "https://github.com/$github_login/$REPO"
        echo "Done"
    fi
}

github_revoke() {
    echo "Delete starterupper-script under Personal access tokens"
    file_open "https://github.com/settings/applications"
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

# Clean up everything but the repo (BEWARE!)
clean() {
    github_revoke
    sed -i s/.*github.com.*// ~/.ssh/known_hosts
    git config --global --unset user.name
    git config --global --unset user.email
    git config --global --unset github.login
    git config --global --unset github.token
    rm -f ~/.ssh/id_rsa*
}

if [ $# == 0 ]; then
    github_setup
elif [[ $1 == "clean" ]]; then
    clean
elif [[ $1 == "collaborators" ]]; then
    github_add_collaborators
fi
