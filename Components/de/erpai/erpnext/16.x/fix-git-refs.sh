#!/bin/bash

# Configures git for Frappe apps so remote branches/tags are fetchable, while
# keeping the clone shallow (depth=1 per ref) to save disk space.
#
# Usage:
#   ./fix-git-refs.sh apps/myapp             # make every remote branch switchable (depth=1 each)
#   ./fix-git-refs.sh apps/myapp <version> [<repository-url>]

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <app-path> [<branch-or-tag>]"
    echo "Example: $0 apps/myapp"
    echo "Example: $0 apps/myapp version-16"
    exit 1
fi

APP_PATH="$1"
VERSION="$2"
REPOSITORY_URL="$3"

# Check if directory exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Directory $APP_PATH does not exist"
    exit 1
fi

# Check if it's a git repository
if [ ! -d "$APP_PATH/.git" ]; then
    echo "Error: $APP_PATH is not a git repository"
    exit 1
fi

cd "$APP_PATH"

# Configure SSH to auto-accept new host keys (but still verify known ones)
echo "🔐 Configuring SSH host key verification (accept-new)..."
git config core.sshCommand "ssh -o StrictHostKeyChecking=accept-new"
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"

if [ -n "$REPOSITORY_URL" ]; then
    REMOTE="upgrade-source"
    if git remote get-url "$REMOTE" >/dev/null 2>&1; then
        git remote set-url "$REMOTE" "$REPOSITORY_URL"
    else
        git remote add "$REMOTE" "$REPOSITORY_URL"
    fi
else
    REMOTE=$(git remote | head -n 1)
fi
if [ -z "$REMOTE" ]; then
    echo "❌ No remote found"
    exit 1
fi
echo "🌐 Remote: $REMOTE"

if [ -n "$VERSION" ]; then
    # Targeted mode: resolve $VERSION as a branch or tag directly on the
    # remote (not from local state) and fetch/switch to exactly that ref at
    # depth=1. Avoids fetching every branch just to pin one version.
    echo "🎯 Resolving '$VERSION' on $REMOTE (branch or tag)..."

    REMOTE_REFS=$(git ls-remote --heads --tags "$REMOTE" \
        "refs/heads/$VERSION" "refs/tags/$VERSION" 2>/dev/null) || {
        echo "❌ Could not query '$VERSION' on $REMOTE"
        exit 1
    }

    CURRENT_REF=""
    if printf '%s\n' "$REMOTE_REFS" | grep -Fq "refs/heads/$VERSION"; then
        echo "🌿 '$VERSION' is a branch"
        git fetch --depth=1 --no-tags "$REMOTE" "+refs/heads/$VERSION:refs/remotes/$REMOTE/$VERSION"
        git reset --hard "$REMOTE/$VERSION"
        git switch -C "$VERSION" "$REMOTE/$VERSION"
        CURRENT_REF="$VERSION"
        echo "✅ Switched $APP_PATH to branch $VERSION (@ $REMOTE/$VERSION, depth=1)"
    elif printf '%s\n' "$REMOTE_REFS" | grep -Fq "refs/tags/$VERSION"; then
        echo "🏷️  '$VERSION' is a tag"
        git fetch --depth=1 --no-tags "$REMOTE" "+refs/tags/$VERSION:refs/tags/$VERSION"
        git reset --hard "refs/tags/$VERSION"
        git switch --detach "refs/tags/$VERSION"
        echo "✅ Switched $APP_PATH to tag $VERSION (detached HEAD, depth=1)"
    else
        echo "❌ '$VERSION' is neither a branch nor a tag on $REMOTE"
        exit 1
    fi

    # Fetching a new depth=1 tip does not free anything by itself: old
    # branches/tags and the history they still point at stay on disk until
    # nothing references them and gc actually removes them. Drop every other
    # local branch/tag/remote-tracking ref for this app, then prune, so only
    # $VERSION's single commit remains.
    echo "🧹 Dropping stale local refs..."
    git for-each-ref --format='%(refname:short)' refs/heads/ \
        | grep -Fvx "$CURRENT_REF" | xargs -r -n1 git branch -D
    git for-each-ref --format='%(refname:short)' refs/remotes/ \
        | grep -Fvx "$REMOTE/$VERSION" | xargs -r -n1 git branch -dr
    git for-each-ref --format='%(refname:short)' refs/tags/ \
        | grep -Fvx "$VERSION" | xargs -r -n1 git tag -d
    git reflog expire --expire=now --expire-unreachable=now --all
    git gc --prune=now --quiet
    exit 0
fi

echo "🔧 Configuring git to fetch all remote refs for $APP_PATH"

# Show current fetch configuration
echo "📋 Current fetch refspec:"
git config --get-all "remote.$REMOTE.fetch" || echo "  (none configured)"

# Configure git to fetch all remote branches
echo "⚙️  Setting fetch refspec to get all remote branches..."
git config "remote.$REMOTE.fetch" "+refs/heads/*:refs/remotes/$REMOTE/*"

echo "✅ Updated fetch configuration"

# Fetch all refs, but keep each branch at depth=1 (tip commit only). This
# preserves the disk savings of the original shallow clone while still
# allowing local switching between branches and repeated re-fetching to
# pick up updates.
echo "📥 Fetching all remote branches (depth=1, tip commit only)..."
git fetch --depth=1 --no-tags --prune "$REMOTE"

echo ""
echo "📋 Remote branches now available:"
BRANCH_COUNT=$(git branch -r | grep "^  $REMOTE/" | wc -l)
echo "  Count: $BRANCH_COUNT"

# Branches that moved or disappeared upstream leave their old commits
# unreachable locally; a plain fetch never deletes that data, only gc does.
git reflog expire --expire=now --expire-unreachable=now --all
git gc --prune=now --quiet

echo ""
echo "🎉 Git configured to fetch all remote branches for $APP_PATH"
echo "💡 Future git fetch commands will automatically get all remote branches"
