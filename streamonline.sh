#!/usr/bin/env sh
trap cleanup EXIT INT
function cleanup(){ rm "$sloc/${streamer}prog_state.txt" > /dev/null 2>&1; }
# detect missing commands
depCommands=("streamlink" "xdg-open" "notify-send" "figlet" "systemctl" "sed" "grep" "cut" "rev" "date" "find" "mkdir" "nohup" "printf" "jq")
for cmd in "${depCommands[@]}"; do
  if ! which $cmd > /dev/null 2>&1; then
    missing_commands+=("$cmd")
  fi
done
if [ ${#missing_commands[@]} -gt 0 ]; then
  for cmd in "${missing_commands[@]}"; do
    command-not-found "$cmd"
  done
  exit 127
fi

mkdir "$HOME/.local/share/streamonline" > /dev/null 2>&1
sloc="$HOME/.local/share/streamonline"

while getopts "hlqs:S:D:q:c:HR:" flag; do
  case $flag in
    l)
      figlet StreamOnline
    ;;
    q) # silent mode
    STREAMONLINE_SILENT_MODE='thisisdoesntmeananythingsinceitonlychecksifthevariableexistssoimjustgoingtotellyoutowatchaZentreyastream'
    ;;
    h) # show help
    self_disable=TRUE
    printf "streamonline: check if a streamer is online
    -h            : show this help
    -H hang and do nothing for 9999999999 seconds
    -S [streamer] : setup automatic stream checking for [streamer]
    -D [streamer] : remove systemd units for automatic checking for [streamer]
    -c [streamer] : check the status of [streamer], primarily for use in with other scripts and programs -->(requires -s)<--
    -s [host site]the site to connect to and the required syntax to connect
        \033[0;31m1. (do not include the streamer name)
        2. (needs https:// - otherwise it will not work)
        3. (this will be inserted exactly as typed, make sure streamlink (used for checking) can understand it and supports it)\033[0m\n"
    ;;
    S) # generate files
      self_disable=TRUE
      # make sure directories exist
      mkdir "$HOME/.local/share/systemd/"
      mkdir "$HOME/.local/share/systemd/user/"
      
      # create service unit
      printf "[Unit]\nDescription=\"Execute streamonline and check for $OPTARG\"\n[Service]\nType=oneshot\nKillMode=process\nExecStart=/usr/bin/env bash $HOME/.local/bin/streamonline $OPTARG\n[Install]\nWantedBy=streamonline_$OPTARG.timer" > $HOME/.local/share/systemd/user/streamonline_$OPTARG.service
      
      # configure the timer unit
      FIRST_THIRD="[Unit]\nDescription=Run every 15 minutes or at chosen times of day\n[Timer]\nOnCalendar="
      LAST_THIRD="\nAccuracySec=1min\nUnit=streamonline_$OPTARG.service\n[Install]\nWantedBy=timers.target"
      
      # lets take a card from the KDE playbook and make this program configurable
      printf "enter '1' for daytime\n      '2' for anytime\n      '3' for custom\n>>> "
      read TIME_CHOICE
      case $TIME_CHOICE in
        1) OTHER_THIRD="7:00,7:15,7:30,7:45,8:00,8:15,8:30,8:45,9:00,9:15,9:30,9:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30" ;;
        2) OTHER_THIRD="0:00,0:15,0:30,0:45,1:00,1:15,1:30,1:45,2:00,2:15,2:30,2:45,3:00,3:15,3:30,3:45,4:00,4:15,4:30,4:45,5:00,5:15,5:30,5:45,6:00,6:15,6:30,6:45,7:00,7:15,7:30,7:45,8:00,8:15,8:30,8:45,9:00,9:15,9:30,9:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30,20:45,21:00,21:15,21:30,21:45,22:00,22:15,22:30,22:45,23:00,23:15,23:30,23:45" ;;
        3)
          printf "\n\nhere are some times for you to copy & paste\n0:00,0:15,0:30,0:45,1:00,1:15,1:30,1:45,2:00,2:15,2:30,2:45,3:00,3:15,3:30,3:45,4:00,4:15,4:30,4:45,5:00,5:15,5:30,5:45,6:00,6:15,6:30,6:45,7:00,7:15,7:30,7:45,8:00,8:15,8:30,8:45,9:00,9:15,9:30,9:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30,20:45,21:00,21:15,21:30,21:45,22:00,22:15,22:30,22:45,23:00,23:15,23:30,23:45\n\n"
          printf "enter the times of day you want to check (in 24 hour time, seperatated by commas, do it this way or it wont work)\n>>> "
          read OTHER_THIRD
          if [ "$OTHER_THIRD" = "" ]; then
            printf "Error: input invalid\n"
            exit 1
          fi
        ;;
        *) echo "streamonline: invalid option, please try again"; exit 1;;
      esac
      
      # create timer unit file
      printf "${FIRST_THIRD}${OTHER_THIRD//,/\\nOnCalendar=}${LAST_THIRD}" > $HOME/.local/share/systemd/user/streamonline_$OPTARG.timer
      
      # begin config file creation
      printf "\nDo you want to open the stream with xdg-open (1) or streamlink (2)\n>>> "
      read chosen_client
      case $chosen_client in
        1) chosen_client="xdg_open";stream_quality="best";;
        2) chosen_client="streamlink"
          printf "\nWhat quality do you want? 160p, 360p, 480p, 720p (available rarely), 720p60 (available usually), 1080p (available rarely) 1080p60 (available usually - default)-- please be sure your stream supports at least one, otherwise streamlink will not launch\n(leave empty for best quality)\n>>> "
          read stream_quality
          if [ -z $stream_quality ]; then
            stream_quality="best"
          fi
          printf "Enter additional arguments to be passed to streamlink when stream is launched\n>>> "
          read ADDITIONAL_ARGS
        ;;
        3)
          chosen_client="command"
          printf "Enter shell command to execute\n>>> "
          read command
        ;;
        *) echo "streamonline: invalid option, please try again\n"; exit 1;;
      esac
      printf "Enter the site to connect to and the required syntax to connect\n\033[0;31m1. (do not include the streamer name - it must be at the end)\n2. (with https:// - otherwise it will not work)\n3. (this will be inserted exactly as typed, make sure your browser (or streamlink) can understand it)\033[0m\nenter the site to connect to and the required syntax to connect :\n>>> "
      read host_site
      
      #custom notify_text styling
      # TODO add this
      printf "\nWhat notification style do you want? URL (1), stream title (2), category + stream title (3)\n>>> "
      read chosen_notify
      case $chosen_notify in
        1) chosen_notify='host_link';;
        2) chosen_notify='name';;
        3) chosen_notify='name_cat';;
         *) printf "streamonline: invalid option, please try again\n"; exit 1;;
      esac
      printf "\nWhat notification priority do you want? Low (1), Normal (2), Critical (3)\n>>> "
      read priority
      case $priority in
        1) priority='low';;
        2) priority='normal';;
        3) priority='critical';;
         *) printf "streamonline: invalid option, please try again\n"; exit 1;;
      esac
      
      # add config file
      printf "000\n$chosen_client\n$stream_quality\n$host_site\n$chosen_notify\n$ADDITIONAL_ARGS\n$command\n$priority" > "$HOME/.local/share/streamonline/${OPTARG}stream_state.txt"
      # end config file creation
      
      # enable and start the modules for $OPTARG
      systemctl --user enable "streamonline_$OPTARG.timer"
      systemctl --user start "streamonline_$OPTARG.timer"
      systemctl --user enable "streamonline_$OPTARG.service"
      systemctl --user daemon-reload
      systemctl --user status "streamonline_$OPTARG.timer"
      systemctl --user status "streamonline_$OPTARG.service"
      systemctl --user start "streamonline_$OPTARG.service"
      printf "##############################################\nsuccess\n"
    ;;
    D) # delete files
      self_disable=TRUE
      # delete and disable modules for $OPTARG
      systemctl --user stop "streamonline_$OPTARG.timer"
      systemctl --user stop "streamonline_$OPTARG.service"
      systemctl --user disable "streamonline_$OPTARG.timer"
      systemctl --user disable "streamonline_$OPTARG.service"
      systemctl --user daemon-reload
      rm "$HOME/.local/share/systemd/user/streamonline_$OPTARG.timer"
      rm "$HOME/.local/share/systemd/user/streamonline_$OPTARG.service"
      rm "$HOME/.local/share/streamonline/${OPTARG}stream_state.txt"
    ;;
    c) # check only, no special stuff
      mode_return="returnstreamer"
      STREAMONLINE_SILENT_MODE='67'
      streamer=$OPTARG
    ;;
    s) # pain.
      host=$OPTARG
    ;;
    R) # pain.
      self_disable=TRUE
      sed -i '1s/.*/000/' "$sloc/${OPTARG}stream_state.txt"

    ;;
    H) # debugging.
      sleep 9999999999
    ;;
    \?)
      self_disable=TRUE
      echo "streamonline: invalid option, see help for instructions"
    ;;
  esac
done

function toconsole() {
  if [ -z "${STREAMONLINE_SILENT_MODE}" ]; then
    echo $1
  fi
}
# dont mess with this, its goofy
function returnStreamData(){ echo "$streamData"; }
function fallbackValue(){
  if [ "$1" == "" ]; then
    printf "$2"
  else
    printf "$1"
  fi
}
function cleanup(){ rm "$sloc/${streamer}prog_state.txt"; }
function canRun(){
  # run anyway if lockfile more than 720 minutes old is found
  if [ ! -f "$sloc/${streamer}prog_state.txt" ] || [ $(find "$sloc/${streamer}prog_state.txt" -mmin +720) ]; then
    printf "true"
  else
    printf "false"
  fi
}

# chaos ensues
if [ -z "${self_disable}" ]; then
  if [ -z "${mode_return}" ]; then streamer=$1; fi
  if [ -z "${mode_return}" ]; then todaysDateNumber=$(date '+%j'); else todaysDateNumber="returnX"; fi
  if [ -z "${mode_return}" ]; then
    doesExist=$( sed '1!d' "$sloc/${streamer}stream_state.txt" | grep -si -m 1 "$todaysDateNumber")
    mode="$(fallbackValue "$(sed '2!d' "$sloc/${streamer}stream_state.txt")" 'xdg_open')"
    quality="$(fallbackValue "$(sed '3!d' "$sloc/${streamer}stream_state.txt")" 'best' )"
    host="$(sed '4!d' "$sloc/${streamer}stream_state.txt")"
    notify_text="$(fallbackValue "$(sed '5!d' "$sloc/${streamer}stream_state.txt")" 'name_cat' )"
    ADDITIONAL_ARGS="$(sed '6!d' "$sloc/${streamer}stream_state.txt")"
    command="$(sed '7!d' "$sloc/${streamer}stream_state.txt")"
    priority="$(fallbackValue "$(sed '8!d' "$sloc/${streamer}stream_state.txt")" 'normal' )"
  fi
  if [ -z "${doesExist}" ]; then
    # Are we already running?
    if canRun 2> /dev/null | grep -sq true; then
      if [ -z "${mode_return}" ]; then printf "busy" > "$sloc/${streamer}prog_state.txt"; fi
      streamData="$(streamlink --json "${host}${streamer}")"
      # this grabs lines from json and trims them for our use, replace title with desired info in a new option and make a PR:
      # returnStreamData | jq .metadata.title | cut -c 2- | rev | cut -c 2- | rev
      if returnStreamData | grep -sq '"streams"'; then
          toconsole "stream found."
          if [ -z "${mode_return}" ]; then
          case $notify_text in 
            host_link) notify_text="${host}${streamer}" && notify_title="$streamer" ;;
            name) notify_text="$(returnStreamData | jq .metadata.title | cut -c 2- | rev | cut -c 2- | rev)" && notify_title="$streamer" ;;
            name_cat) notify_text="$(returnStreamData | jq .metadata.title | cut -c 2- | rev | cut -c 2- | rev )" && notify_title="$(returnStreamData | jq .metadata.category | cut -c 2- | rev | cut -c 2- | rev )" ;;
          esac
            if [ "$(notify-send -t 0 "${notify_title}" "${notify_text}" -u "${priority}" -a "${streamer} is online!" -A 'Open Stream' -A 'Nope')" -eq '0' ]; then
              case $mode in
                xdg_open) nohup xdg-open "$host$streamer" & > /dev/null 2>&1;;
                streamlink) nohup streamlink $ADDITIONAL_ARGS --title "{author} - {category} - {title}" "$host$streamer" $quality & > /dev/null 2>&1 ;;
                command) nohup $command & > /dev/null 2>&1  ;;
                *) echo "streamonline:  $mode is an unsupported mode, exiting";;
              esac
            fi
          else
            printf "\033[0;32m$streamer is online\033[0m\n"
          fi
          if [ -z "${mode_return}" ]; then
            streamstate="$(cat "$sloc/${streamer}stream_state.txt")"
            yesterdaysDateNumber="$(sed '1!d' "$sloc/${streamer}stream_state.txt")" > /dev/null 2>&1
            rm "$sloc/${streamer}stream_state.txt"
            printf "${streamstate//$yesterdaysDateNumber/$todaysDateNumber}" > "$sloc/${streamer}stream_state.txt"
          fi
      else
        printf "\033[0;31m$streamer is offline\033[0m\n"
      fi
    else
      toconsole "program already active, exiting."
      alreadyActive="inpoopments"
      trap - EXIT
      exit 0
    fi
  else
    toconsole "already returned a stream for \"${streamer}\" today"
  fi
  if [ -z "${alreadyActive}" ]; then
    trap - EXIT
    cleanup > /dev/null 2>&1
  fi
else
  trap - EXIT
fi
exit 0