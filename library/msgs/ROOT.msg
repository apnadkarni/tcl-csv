namespace eval tclcsv {
    ::msgcat::mcflmset {
        encoding_l     "Character encoding"

        header_line_l  "First line contains a header"
        skip_empty_l   "Skip lines that are empty"
        quote_doubled_l "Quotes are represented by doubling"
        ignore_leading_space_l "Ignore leading space in fields"
        
        delimiter_char_l Delimiter
        comment_char_l "Comment character"
        quote_char_l   "Quote character"
        escape_char_l  "Escape character"
        
        none_l         None
        space_l        Space
        tab_l          Tab
        hash_l         "Hash (#)"
        semicolon_l    "Semicolon (;)"
        comma_l        Comma
        dquote_l       "Double quote (\")"
        squote_l       "Single quote (')"
        backslash_l    "Backslash (\)"
        other_l        Other
        
        include_l      Include
        heading_l      Heading
        type_l         Type
    }
}
