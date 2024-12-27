#!/bin/bash

# Configuration
API_URL="http://IP:5055/api/v1"
API_KEY="YOUR_JELLYSEERR_API_KEY"

# Ask user for keyword
read -p "Enter the keyword to search: " KEYWORD

# Counters for statistics
TOTAL_PROCESSED=0
ALREADY_BLACKLISTED=0
SUCCESSFULLY_ADDED=0
FAILED=0

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed"
    exit 1
fi

# 1. Search for keyword ID
echo "Searching for keyword '$KEYWORD'..."
KEYWORD_SEARCH_RESPONSE=$(curl -s -H "X-Api-Key: $API_KEY" \
    "$API_URL/search/keyword?query=$(echo $KEYWORD | sed 's/ /%20/g')")

# Check if response is valid JSON
if ! echo "$KEYWORD_SEARCH_RESPONSE" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON response"
    exit 1
fi

KEYWORD_ID=$(echo "$KEYWORD_SEARCH_RESPONSE" | jq -r '.results[0].id')

if [ -z "$KEYWORD_ID" ] || [ "$KEYWORD_ID" = "null" ]; then
    echo "Error: Unable to find ID for keyword '$KEYWORD'"
    exit 1
fi

echo "Keyword ID found: $KEYWORD_ID"

# 2. Get list of movies with this keyword
echo "Retrieving movies with this keyword..."
MOVIES_RESPONSE=$(curl -s -H "X-Api-Key: $API_KEY" \
    "$API_URL/discover/keyword/$KEYWORD_ID/movies")

# Check if response is valid JSON
if ! echo "$MOVIES_RESPONSE" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON response for movie list"
    exit 1
fi

# Extract movie list
TOTAL_PAGES=$(echo "$MOVIES_RESPONSE" | jq -r '.totalPages')
if [ -z "$TOTAL_PAGES" ] || [ "$TOTAL_PAGES" = "null" ]; then
    echo "Error: Unable to determine total number of pages"
    exit 1
fi

echo "Total number of pages to process: $TOTAL_PAGES"

# Process each page
for ((page=1; page<=TOTAL_PAGES; page++)); do
    echo "Processing page $page/$TOTAL_PAGES..."
    
    MOVIES_PAGE_RESPONSE=$(curl -s -H "X-Api-Key: $API_KEY" \
        "$API_URL/discover/keyword/$KEYWORD_ID/movies?page=$page")
    
    # Check if response is valid JSON
    if ! echo "$MOVIES_PAGE_RESPONSE" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response for page $page"
        continue
    fi
    
    # Extract and process each movie
    while IFS= read -r TMDB_ID && IFS= read -r TITLE; do
        if [ -n "$TMDB_ID" ] && [ -n "$TITLE" ] && [ "$TITLE" != "null" ]; then
            echo -n "Processing movie: $TITLE (ID: $TMDB_ID)... "
            ((TOTAL_PROCESSED++))
            
            # Create JSON for blacklist request
            BLACKLIST_DATA=$(jq -n \
                --arg tmdbId "$TMDB_ID" \
                --arg title "$TITLE" \
                '{
                    tmdbId: ($tmdbId|tonumber),
                    title: $title,
                    mediaType: "movie",
                    user: 1,
                    media: {
                        status: 0
                    }
                }')
            
            # Add to blacklist
            BLACKLIST_RESPONSE=$(curl -s -X POST \
                -H "X-Api-Key: $API_KEY" \
                -H "Content-Type: application/json" \
                -d "$BLACKLIST_DATA" \
                "$API_URL/blacklist")
            
            # Check blacklist addition response
            if [[ "$BLACKLIST_RESPONSE" == *"Item already blacklisted"* ]]; then
                echo "Already in blacklist"
                ((ALREADY_BLACKLISTED++))
            else
                echo "Successfully added"
                ((SUCCESSFULLY_ADDED++))
                if [[ -n "$BLACKLIST_RESPONSE" ]]; then
                    echo "Response: $BLACKLIST_RESPONSE"
                else
                    echo "Successfully added"
                fi
            fi
        fi
    done < <(echo "$MOVIES_PAGE_RESPONSE" | jq -r '.results[] | (.id, .title)')
    
    # Display intermediate statistics
    echo "--- Intermediate Statistics ---"
    echo "Movies processed: $TOTAL_PROCESSED"
    echo "Already blacklisted: $ALREADY_BLACKLISTED"
    echo "Successfully added: $SUCCESSFULLY_ADDED"
    echo "Failures: $FAILED"
    echo "--------------------------------"
    
    # Pause between pages
    sleep 1
done

# Display final statistics
echo "=== Final Statistics ==="
echo "Total movies processed: $TOTAL_PROCESSED"
echo "Already blacklisted: $ALREADY_BLACKLISTED"
echo "Successfully added: $SUCCESSFULLY_ADDED"
echo "Failures: $FAILED"
echo "=========================="

echo "Processing completed"