FUNCTION FACTORIAL \ n \
    VAL n IF
        VAL n -1 + SELF VAL n *
    ELSE
        1
    THEN
ENDFUNC
