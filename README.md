# livecodeExif
Livecode library for reading and manipulating image Exif data.

www.livecode.com

## How it works
Copy the code of file **libExif.lcsrcipt** in your stack.
Use the code:

    put URL "binfile:/home/user/myImage.jpg" into pData
    put exifProcessFile(pData,true) into myList
    answer myList

The **OpenStack** or the **exifResetTags** messages create all custom properties needed.
You may use **exifProcessFileArray(pData,true)** the get the data in array form.

## How contribute
The **exifResetTags** contains how to interprete the EXIF code, you could add more there.
