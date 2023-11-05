#!/usr/bin/python

import os
import sys
import signal
try:
    import git
except:
    os.system("pip3 install GitPython")
    os.exit(1)
    
import json
import threading

from pprint import pprint


def strg_c_handler(signum, frame):
    print("Strg+C wurde gedrückt. Beende das Programm.")
    sys.exit(1)

signal.signal(signal.SIGINT, strg_c_handler)

def my_print( text ):
    print("\033[01;32m" + text + "\033[00m")

def my_print_red( text ):
    print("\033[01;31m" + text + "\033[00m")
    

def print_line_text( text ):
    print("\033[01;33m------------------------------  \033[01;32m " + text + " \033[01;33m ---------------------------------------\033[00m")

with open('infos.json', 'r') as json_file:
    infos = json.load(json_file)



def build_hash_list():
    global git_hash_list
    
    repo = git.Repo("uclibc-ng")
    commits = list(repo.iter_commits())
    
    index = 0
    
    git_hash_list=[]
    for commit in commits:
        git_hash_list.append( { "INDEX": index, "HASH": commit.hexsha, "TAG": False, "NAME":"" , "WORKING": False} )
        index += 1
        #print(commit.hexsha)

    # Alle Tags im Repository abrufen
    tags = repo.tags

    # Die SHA-1-Hashes der Tags ausgeben
    for tag in tags:
        for h in git_hash_list:
            if h["HASH"] == tag.commit.hexsha:
                h["TAG"] = True
                h["NAME"] = tag.name
                #print( h )
                #sys.exit(1)
                break
        

    #for h in git_hash_list:
    #    print( h )

    #sys.exit(1)

    return git_hash_list


def run_command(command):
    os.system(command)
    
def run_build_thread( cmd ):
    
    command_thread = threading.Thread(target=run_command, args=(cmd,) )
    command_thread.start()
    command_thread.join()



def print_bisec_info():
    global git_hash_list, bisec_info
    
    diff = bisec_info["GOOD"] - bisec_info["BAD"]
    print("\033[01;33m------------------------------  \033[01;32mbisec status \033[01;33m ---------------------------------------\033[00m")
    print("good - bad:\033[01;32m " + str( diff ) + "\033[00m commits" )
    print("Last Good : \033[01;32m" + git_hash_list[ bisec_info["GOOD"] ]["HASH"] + "\033[00m")
    print("Bad       : \033[01;31m" + git_hash_list[ bisec_info["BAD"] ]["HASH"] + "\033[00m")
    os.system('cd uclibc-ng; git log --format="Author    : %an <%ae>%nDate      : %ad%nMessage   : %s" -n 1 ' + git_hash_list[ bisec_info["BAD"] ]["HASH"] )
    #print("\033[01;33m-------------------------------------------------------------------------------------\033[00m")
    
    

def get_next_try_hash( ):
    global git_hash_list, bisec_info
    
    diff = bisec_info["GOOD"] - bisec_info["BAD"]
    #pprint( bisec_info )
    #print( diff )
    
    return git_hash_list[ bisec_info["BAD"] + int( diff / 2 ) ];
    

def build_hash( git_hash ):
    global bisec_info
    
    print("\033[01;33m------------------------------  \033[01;32mchecking git hash " + git_hash["HASH"] + "  \033[01;33m------------------------------------------------------\033[00m")
    print("Log : build_" + git_hash["HASH"] + ".log")
    os.system("cd uclibc-ng; git -c advice.detachedHead=false checkout " + git_hash["HASH"] )
    os.system("cd uclibc-ng; PAGER= git log -1")
    ret = os.system("CROSS_COMPILE=" + infos["CONFIG_GCC_PREFIX"] + " make -C uclibc-ng -j20 > build_" + git_hash["HASH"] + ".log 2>&1")
    if ret == 0:
        git_hash["WORKING"] = True
        my_print("    OK")
        bisec_info["GOOD"] = git_hash["INDEX"]
        return ret
    
    bisec_info["BAD"] = git_hash["INDEX"]
    my_print_red("    ERROR")
    return ret
    

#pprint( infos )

print("")
print("  artifact rebuild and bisec Tool")
print("")


build_repo = "uclibc-ng"


repo = "https://cgit.uclibc-ng.org/cgi/cgit/uclibc-ng.git"
repo = "https://github.com/lordrasmus/uclibc-ng"

if not os.path.exists( "uclibc-ng_orig" ) and len( sys.argv ) == 1:

    my_print("git clone " + repo)
    os.system("git clone " + repo + " uclibc-ng_orig")
    


if len( sys.argv ) > 1 :
    print("   using repo : " + sys.argv[1] )
    print("")
    
    if not os.path.exists( sys.argv[1] ):
        print("")
        print("Error Path : "+ sys.argv[1] + "not found" )
        print("")
        sys.exit(1)
    
    print_line_text("rsync source tree to uclibc-ng")
    os.system("rsync --info=progress2 -a " +  sys.argv[1] + " uclibc-ng/")
    
else:
    print("   using repo : " + repo )
    print("")
    
    print_line_text("rsync source tree to uclibc-ng")
    os.system("rsync --info=progress2 -a uclibc-ng_orig/ uclibc-ng/")





if not os.path.exists( infos["CONFIG_TOOLCHAIN"] ):
    print_line_text("extract toolchain")
    os.system("tar -xaf " + infos["CONFIG_TOOLCHAIN"] + ".tar.xz" )
    
os.environ["PATH"] += ":" + os.getcwd() + "/" + infos["CONFIG_TOOLCHAIN"] + "/usr/bin"

if not os.path.exists("linux-" + infos["CONFIG_KERNEL_VERS"] ):
    print_line_text("extract Kernel " + infos["CONFIG_KERNEL_VERS"] )
    os.system("tar -xaf linux-" + infos["CONFIG_KERNEL_VERS"] + ".tar.xz" )
    
if not os.path.exists("uclibc-ng/linux-header"):
    print_line_text("install Linux Header")
    os.system("make -C linux-" + infos["CONFIG_KERNEL_VERS"] + " INSTALL_HDR_PATH=$(pwd)/uclibc-ng/linux-header headers_install ARCH=" + infos["CONFIG_KERNEL_ARCH"] )

if not os.path.exists("uclibc-ng/.config"):
    print_line_text("copy .config")
    os.system("cp uclibc-ng-config uclibc-ng/.config")
    
print_line_text("patch .config KERNEL_HEADERS")
os.system("sed -i 's|KERNEL_HEADERS=.*|KERNEL_HEADERS=\"linux-header/include\"|g'  uclibc-ng/.config")




print_line_text("loading git log hashes")
build_hash_list()




print_line_text("check HEAD uClibc-ng for building error ")
 
print("rebuild command : ")
print("      PATH=$PATH:$(pwd)/" + infos["CONFIG_TOOLCHAIN"] + "/usr/bin CROSS_COMPILE=" + infos["CONFIG_GCC_PREFIX"] + " make -C uclibc-ng")

ret = os.system("CROSS_COMPILE=" + infos["CONFIG_GCC_PREFIX"] + " make -C uclibc-ng -j20 > build_init.log 2>&1 ")
#ret = 0
if ret == 0:
    print("No Error detected")
    print("Log : build_init.log")
    print("")
    
    print("")
    sys.exit(0)
    
    
bisec_info = {}    

print("Build \033[01;31m Failed \033[00m")
    
print_line_text("starting bisec")

my_print("                  search last working tag")


bisec_info["BAD"] = git_hash_list[0]["INDEX"]


for git_hash in git_hash_list:
    #print( git_hash )
    
    if git_hash["TAG"] == False: continue
    
    if build_hash( git_hash ) == 0:
        break
    


while True:
    print_bisec_info()
    
    try_hash = get_next_try_hash()
    build_hash( try_hash )
    
    if ( bisec_info["GOOD"] - bisec_info["BAD"] ) < 2 :
        break
        


#pprint( bisec_info )
print_bisec_info()
print("\033[01;33m-------------------------------------------------------------------------------------\033[00m")    
#os.system("cd uclibc-ng; PAGER= git log -1")    


#os.system("cd uclibc-ng ; git pull")    


