# frozen_string_literal: true

json.page page_scope.current_page
json.per_page page_scope.limit_value
json.total page_scope.total_count
