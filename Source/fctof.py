# remove comments from bootstrap.fc and create bootstrap.f

converted: str = ""

with open("bootstrap.fc") as file:
    converted = " ".join(
        [line.split(";")[0].strip() 
         for line in file.readlines() 
         if line.split(";")[0].strip()]
         ).strip() + "\n"

with open("bootstrap.f", "w") as file:
    file.write(converted)