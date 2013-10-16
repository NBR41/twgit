#!/bin/bash

##
# twgit
#
#
#
# Copyright (c) 2011 Twenga SA
# Copyright (c) 2012 Geoffroy Aubry <geoffroy.aubry@free.fr>
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance
# with the License. You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License
# for the specific language governing permissions and limitations under the License.
#
# @copyright 2011 Twenga SA
# @copyright 2012 Geoffroy Aubry <geoffroy.aubry@free.fr>
# @license http://www.apache.org/licenses/LICENSE-2.0
#



##
# Affiche l'aide de la commande tag.
#
# @testedby TwgitHelpTest
#
function usage () {
    echo; CUI_displayMsg help 'Usage:'
    CUI_displayMsg help_detail '<b>twgit hotfix <action></b>'
    echo; CUI_displayMsg help 'Available actions are:'
    CUI_displayMsg help_detail '<b>finish [-I]</b>'
    CUI_displayMsg help_detail "    Merge current hotfix branch into '$TWGIT_STABLE', create a new tag and push."
    CUI_displayMsg help_detail '    Add <b>-I</b> to run in non-interactive mode (always say yes).'; echo
    CUI_displayMsg help_detail '<b>list [-F]</b>'
    CUI_displayMsg help_detail '    List current hotfix. Add <b>-F</b> to do not make fetch.'; echo
    CUI_displayMsg help_detail '<b>push</b>'
    CUI_displayMsg help_detail "    Push current hotfix to '$TWGIT_ORIGIN' repository."
    CUI_displayMsg help_detail "    It's a shortcut for: \"git push $TWGIT_ORIGIN $TWGIT_PREFIX_HOTFIX…\""; echo
    CUI_displayMsg help_detail '<b>remove <hotfixname></b>'
    CUI_displayMsg help_detail '    Remove both local and remote specified hotfix branch.'
    CUI_displayMsg help_detail '    Despite that, create the same tag as finish action to clearly distinguish'
    CUI_displayMsg help_detail '    the next hotfix from this one.'
    CUI_displayMsg help_detail "    Prefix '$TWGIT_PREFIX_HOTFIX' will be added to the specified <b><hotfixname></b>."; echo
    CUI_displayMsg help_detail '<b>start</b>'
    CUI_displayMsg help_detail '    Create both a new local and remote hotfix, or fetch the remote hotfix,'
    CUI_displayMsg help_detail '    or checkout the local hotfix.'
    CUI_displayMsg help_detail '    Hotfix name will be generated by incrementing revision of the last tag:'
    CUI_displayMsg help_detail "      v1.2.3 > ${TWGIT_PREFIX_HOTFIX}1.2.4"; echo
    CUI_displayMsg help_detail '<b>[help]</b>'
    CUI_displayMsg help_detail '    Display this help.'; echo
}

##
# Action déclenchant l'affichage de l'aide.
#
# @testedby TwgitHelpTest
#
function cmd_help () {
    usage;
}

##
# Liste les derniers hotfixes.
# Gère l'option '-F' permettant d'éviter le fetch.
#
function cmd_list () {
    process_options "$@"
    process_fetch 'F'

    local hotfixes=$(get_last_hotfixes 1)
    CUI_displayMsg help "Remote current hotfix:"
    display_branches 'hotfix' "$hotfixes"; echo

    alert_dissident_branches
}

##
# Crée un nouveau hotfix à partir du dernier tag.
# Son nom est le dernier tag en incrémentant le numéro de révision : major.minor.(revision+1)
#
function cmd_start () {
    assert_clean_working_tree
    process_fetch

    CUI_displayMsg processing 'Check remote hotfixes...'
    local remote_hotfix="$(get_hotfixes_in_progress)"
    local hotfix
    if [ -z "$remote_hotfix" ]; then
        assert_tag_exists
        local last_tag=$(get_last_tag)
        hotfix=$(get_next_version 'revision')
        local hotfix_fullname="$TWGIT_PREFIX_HOTFIX$hotfix"
        exec_git_command "git checkout -b $hotfix_fullname tags/$last_tag" "Could not check out tag '$last_tag'!"
        process_first_commit 'hotfix' "$hotfix_fullname"
        process_push_branch $hotfix_fullname
    else
        local prefix="$TWGIT_ORIGIN/$TWGIT_PREFIX_HOTFIX"
        hotfix="${remote_hotfix:${#prefix}}"
        CUI_displayMsg processing "Remote hotfix '$TWGIT_PREFIX_HOTFIX$hotfix' detected."
        assert_valid_ref_name $hotfix
        local hotfix_fullname="$TWGIT_PREFIX_HOTFIX$hotfix"
        assert_new_local_branch $hotfix_fullname
        exec_git_command "git checkout --track -b $hotfix_fullname $remote_hotfix" "Could not check out hotfix '$remote_hotfix'!"
    fi
    echo
}

##
# Supprime le hotfix spécifié.
#
# @param string $1 nom court du hotfix
#
function cmd_remove () {
    process_options "$@"
    require_parameter 'hotfix'
    local hotfix="$RETVAL"
    local hotfix_fullname="$TWGIT_PREFIX_HOTFIX$hotfix"
    local tag="$hotfix"
    local tag_fullname="$TWGIT_PREFIX_TAG$tag"

    assert_valid_ref_name $hotfix
    assert_clean_working_tree
    assert_working_tree_is_not_on_delete_branch $hotfix_fullname

    process_fetch
    assert_new_and_valid_tag_name $tag

    # Suppression de la branche :
    assert_clean_stable_branch_and_checkout
    remove_local_branch $hotfix_fullname
    remove_remote_branch $hotfix_fullname

    # Gestion du tag :
    create_and_push_tag "$tag_fullname" "Hotfix remove: $hotfix_fullname"
    echo
}

##
# Merge le hotfix à la branche stable et crée un tag portant son nom.
# Gère l'option '-I' permettant de répondre automatiquement (mode non interactif) oui à la demande de pull.
#
# @param string $1 nom court du hotfix
#
function cmd_finish () {
    process_options "$@"
    assert_clean_working_tree
    process_fetch

    CUI_displayMsg processing 'Check remote hotfix...'
    local remote_hotfix="$(get_hotfixes_in_progress)"
    [ -z "$remote_hotfix" ] && die 'No hotfix in progress!'

    local prefix="$TWGIT_ORIGIN/$TWGIT_PREFIX_HOTFIX"
    hotfix="${remote_hotfix:${#prefix}}"
    local hotfix_fullname="$TWGIT_PREFIX_HOTFIX$hotfix"
    CUI_displayMsg processing "Remote hotfix '$hotfix_fullname' detected."

    CUI_displayMsg processing "Check local branch '$hotfix_fullname'..."
    if has $hotfix_fullname $(get_local_branches); then
        assert_branches_equal "$hotfix_fullname" "$TWGIT_ORIGIN/$hotfix_fullname"
    else
        exec_git_command "git checkout --track -b $hotfix_fullname $TWGIT_ORIGIN/$hotfix_fullname" "Could not check out hotfix '$TWGIT_ORIGIN/$hotfix_fullname'!"
    fi

    # Gestion du tag :
    local tag="$hotfix"
    local tag_fullname="$TWGIT_PREFIX_TAG$tag"
    assert_new_and_valid_tag_name $tag

    assert_clean_stable_branch_and_checkout
    exec_git_command "git merge --no-ff $hotfix_fullname" "Could not merge '$hotfix_fullname' into '$TWGIT_STABLE'!"
    create_and_push_tag "$tag_fullname" "Hotfix finish: $hotfix_fullname"

    # Suppression de la branche :
    remove_local_branch $hotfix_fullname
    remove_remote_branch $hotfix_fullname

    local current_release="$(get_current_release_in_progress)"
    [ ! -z "$current_release" ] \
        && CUI_displayMsg warning "Do not forget to merge '<b>$tag_fullname</b>' tag into '<b>$TWGIT_ORIGIN/$current_release</b>' release before close it! Try on release: git merge --no-ff $tag_fullname"
    echo
}

##
# push du hotfix
#
function cmd_push () {
    process_options "$@"
    local current_branch=$(get_current_branch)

    assert_clean_working_tree
    process_push_branch $current_branch

}


