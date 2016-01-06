token_names = {
  "LPAREN",
  "RPAREN",

  "LBRACK",
  "RBRACK",

  "LBRACE",
  "RBRACE",

  "GT",
  "DOLLAR",
  "NL",
  "RARROW",
  "EQ",
  "PLUS",
  "TILDE",
  "BANG",
  "PIPE",
  "COLON",
  "STAR",
  "COMMA",
  "UNDERSCORE",
  "QUESTION",
  "DASH",
  "DOT",

  "AMP",
  "DYNAMIC",
  "FLAG",
  "FLAGKEY",
  "CHECK",
  "TAGGED",
  "TICKED",
  "MACRO",
  "ANNOT",
  "SLASH",
  "INT",
  "NAME",
  "STRING",

  "EOF"
}

token_ids = {}
for name, index in ipairs(token_names) do
  token_ids[name] = index
end

eats_preceding_newline = {
  [token_ids.GT]       = true,
  [token_ids.RARROW]   = true,
  [token_ids.EQ]       = true,
  [token_ids.COMMA]    = true,
  [token_ids.PIPE]     = true,
  [token_ids.QUESTION] = true,
  [token_ids.RBRACK]   = true,
  [token_ids.RBRACE]   = true,
}

function Lexer(stream)
  local state = {
    index = 0,
    line = 0,
    column = 0,
    tape = nil,
    head = nil,
    recording = false,
    uninitialized = true,
    peek = nil
    final_loc = nil
  }

  function setup()
    stream.setup()
    advance()
    state.uninitialized = false
    skip_lines()
    reset()
  end

  function teardown()
    stream.teardown()
  end

  function reset()
    state.recording = false
    state.tape = nil
    state.final_loc = nil
  end

  function recorded_value()
    if state.tape then
      return table.concat(state.tape, '')
    else
      return nil
    end
  end

  function current_location()
    return {
      input = stream.input_name(),
      index = state.index,
      line = state.line,
      column = state.column
    }
  end

  function advance()
    assert(state.uninitialized or state.head)

    state.index = state.index + 1
    if state.head == "\n" then
      state.line = state.line + 1
      state.column = 0
    else
      state.column = state.column + 1
    end

    if state.recording then
      table.insert(state.tape, state.head)
    end

    state.head = stream.next()
  end

  function record()
    state.recording = true
    state.tape = {}
  end

  function end_record()
    state.recording = false
    end_loc()
  end

  function end_loc()
    state.final_loc = current_location()
  end

  function final_loc()
    return state.final_loc or current_location()
  end

  function next()
    if state.peek then
      local p = state.peek
      state.peek = nil
      return p
    end

    reset()
    local start = current_location()
    local token = process_root()
    local value = recorded_value()
    local final = final_loc()

    assert(token == token_ids.EOF or state.index ~= start.index, 'must advance the stream!')

    return { tokid = token, value = value, range = { start = start, final = final } }
  end

  function peek()
    if not state.peek then
      state.peek = next()
    end

    return state.peek
  end

  function skip_ws()
    end_loc()
    advance_through_ws()
  end

  function advance_through_ws()
    while is_ws(state.head) do advance() end
  end

  function skip_lines()
    end_loc()
    while true do
      advance_through_ws()
      if state.head == '#' then
        while state.head and state.head ~= "\n" do advance() end
      elseif is_nl(state.head) then
        advance()
      else
        break
      end
    end
  end

  function record_ident()
    if not is_alpha(state.head) then error('expected an identifier') end

    record()

    advance()
    while is_ident_char(state.head) do advance() end

    end_record()
  end

  function process_string()
    advance()
    record()

    local level = 1

    while true do
      if state.head == '\\' then
        advance()
      elseif state.head == '{' then
        level = level + 1
      elseif state.head == '}' then
        level = level - 1
      elseif not state.head then
        error('unmatched close brace')
      end

      if level == 0 then
        end_record()
        advance()
        break
      else
        advance()
      end
    end
  end

  function process_root()
    if not state.head then return token_ids.EOF end

    if state.head == '(' then
      advance()
      skip_lines()
      return token_ids.LPAREN
    end

    if state.head == ')' then
      advance()
      skip_ws()
      return token_ids.RPAREN
    end

    if state.head == '[' then
      advance()
      skip_lines()
      return token_ids.LBRACK
    end

    if state.head == ']' then
      advance()
      skip_ws()
      return token_ids.RBRACK
    end

    if state.head == '{' then
      advance()
      skip_lines()
      return token_ids.LBRACE
    end

    if state.head == '}' then
      advance()
      skip_ws()
      return token_ids.RBRACE
    end

    if state.head == "'" then
      advance()
      if state.head == '{' then
        process_string()
        skip_ws()
        return token_ids.STRING
      else
        record_ident()
        return token_ids.STRING
      end
    end

    if state.head == '`' then
      advance()
      record_ident()
      skip_lines()
      return token_ids.TICKED
    end

    if state.head == '=' then
      advance()
      if state.head == '>' then
        advance()
        skip_lines()
        return token_ids.RARROW
      else
        skip_lines()
        return token_ids.EQ
      end
    end

    if state.head == '+' then
      advance()
      skip_ws()
      return Token.PLUS
    end

    if state.head == '$' then
      advance()
      if is_alpha(state.head) then
        record_ident()
        skip_ws()
        return Token.DYNAMIC
      else
        skip_ws()
        return Token.DOLLAR
      end
    end

    if state.head == '>' then
      advance()
      skip_lines()
      return token_ids.GT
    end

    if state.head == '!' then
      advance()
      skip_ws()
      return token_ids.BANG
    end

    if state.head == '?' then
      advance()
      skip_lines()
      return token_ids.QUESTION
    end

    if state.head == '_' then
      advance()
      skip_ws()
      return token_ids.UNDERSCORE
    end

    if state.head == '-' then
      advance()
      if is_ident_char(state.head) then
        record_ident()
        if state.head == ':' then
          advance()
          skip_lines()
          return token_ids.FLAGKEY
        else
          skip_ws()
          return token_ids.FLAG
        end
      end
    end


  end


  return {
    setup = setup,
    teardown = teardown,
    next = next,
    peek = peek
  }
end

function is_nl(char)
  return char == '\r' or char == '\n' or char == ';'
end
