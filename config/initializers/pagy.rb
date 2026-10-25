require "pagy/extras/limit"    # ?limit=N, capped at limit_max
require "pagy/extras/overflow" # a page past the end returns [] instead of raising
require "pagy/extras/headers"  # Link, Current-Page, Page-Items, Total-Pages, Total-Count

Pagy::DEFAULT[:limit] = 25
Pagy::DEFAULT[:limit_max] = 100
Pagy::DEFAULT[:overflow] = :empty_page
Pagy::DEFAULT.freeze
