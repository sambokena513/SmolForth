# remove comments from bootstrap.fc and create bootstrap.f
# also expand macros
# this script is probably horribly slow but it doesn't need to be good
# just to work

class Macro:
    def __init__(self, name: str, body: list[str]) -> None:
        self.name: str = name
        self.body: list[str] = body

    def expand(self, args: list[str]) -> list[str]:
        expanded = self.body.copy()

        for idx, word in enumerate(self.body):
            if word.startswith("$"):
                try:
                    expanded[idx] = args[int(word[1:])]
                except:
                    continue

        return expanded


    def __repr__(self) -> str:
        return f"${self.name} = {" ".join(self.body)}"


def remove_comments(string: str) -> str:
    return " ".join(
        [line.split("//")[0].strip() 
        for line in string.split("\n") 
        if line.split("//")[0].strip()]
        ).strip() + "\n"

def define_macros(string: str) -> tuple[list[str], dict[str, Macro]]:
    words = string.split()
    macros: dict[str, Macro] = {}
    current: str = ""
    indef: bool = False
    idx: int = 0
    end: int = idx

    while idx < len(words):
        word = words[idx]

        if word == "$define":
            indef = True
            macros[words[idx + 1]] = Macro(words[idx + 1], [])
            current = words[idx + 1]
            idx += 2

        elif word == "$enddef":
            indef = False
            idx += 1
            end = idx

        elif indef:
            macros[current].body.append(word)
            idx += 1

        else:
            idx += 1

    return words[end:], macros

def parse_macro_call(s: str) -> tuple[str, list[str], int]:
    i: int = 1
    depth: int = 0
    currarg: int = 0
    consumed: int = 1
    c: str = ""
    name: str = ""
    args: list[str] = [""]
    

    while i < len(s):
        c = s[i]
        if c == " ":
            return name, args, consumed

        if c == "<":
            i += 1
            break

        name += c
        i += 1

    while i < len(s):
        c = s[i]

        if c.strip() == "":
            consumed += 1
            i += 1

        elif c == ">" and depth == 0:
            break

        elif c == "," and depth == 0:
            args.append("")
            currarg += 1
            i += 1

        elif c == "<":
            depth += 1
            args[currarg] += c
            i += 1

        elif c == ">":
            depth -= 1
            args[currarg] += c
            i += 1

        else:
            args[currarg] += c
            i += 1

    return name, args, consumed

def expand_macros(words: list[str], macros: dict[str, Macro]):
    expanded = words

    for i, word in enumerate(words):
        if word.startswith("$"):
            name, args, consumed = parse_macro_call(" ".join(words[i:]))
            expanded = words[:i] + macros[name].expand(args) + words[i+consumed:]
            break

    while True:
        if expanded != words:
            words = expanded

            for i, word in enumerate(words):
                if word.startswith("$"):
                    name, args, consumed = parse_macro_call(" ".join(words[i:]))
                    expanded = words[:i] + macros[name].expand(args) + words[i+consumed:]
                    break
        else:
            return expanded


with open("bootstrap.fc", "r") as inp:
    with open("bootstrap.f", "w") as out:
        out.write(" ".join(expand_macros(*define_macros(remove_comments(inp.read())))) + "\n")