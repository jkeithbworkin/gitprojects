$files = dir -recurse *.docx
foreach ($file in $files ) {
    $mdFile = $file.Name.TrimEnd(".docx") + ".md"
    pandoc -s $file -t markdown_github  -o $mdFile
}