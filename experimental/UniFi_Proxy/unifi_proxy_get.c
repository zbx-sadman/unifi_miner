#include<stdio.h> //printf
#include<string.h>    //strlen
#include<sys/socket.h>    //socket
#include<arpa/inet.h> //inet_addr
 
int main(int argc , char *argv[])
{
    int sock;
    struct sockaddr_in server;
    char message[255] , server_reply[65536];
     
    if (4 != argc)
      {
        printf("[!] To few arguments. Use: %s <IP> <port> <request>\n", argv[0]);
        return 1;
      }

    //Create socket
    sock = socket(AF_INET , SOCK_STREAM , 0);
    if (sock == -1)
    {
        puts("Could not create socket");
    }

    // 1-st arg - addr to connect 
    server.sin_addr.s_addr = inet_addr(argv[1]);
    server.sin_family = AF_INET;
    // 2-nd arg - port to connect 
    server.sin_port = htons(atoi(argv[2]));
 
    //Connect to remote server
    if (connect(sock , (struct sockaddr *)&server , sizeof(server)) < 0)
    {
        puts("connect failed. Error");
        return 1;
    }

    // 3-rd arg - request line
    sprintf(message, "%s\n",argv[3]);
    //Send some data
    if( send(sock , message , strlen(message) , 0) < 0)
    {
        puts("Send failed");
        return 1;
    }
         
    //Receive a reply from the server
    if( recv(sock , server_reply , 2000 , 0) < 0)
    {
        puts("recv failed");
        return 1;
    }
         
    puts(server_reply);

    close(sock);
    return 0;
}
