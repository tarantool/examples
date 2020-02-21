    local param = ...
    local user_id = param.user_id

    local user_books = repository.find('Subscription', {{"$user_id", "==", user_id}})

    local result = {}
    for _, book in pairs(user_books) do
        table.insert(result, book.book_id)
    end

    return json.encode(result)
