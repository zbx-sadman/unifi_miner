#define UNIFI_PROXY_IP "127.0.0.1"
#define UNIFI_PROXY_PORT 7777
#define UNIFI_PROXY_TIMEOUT 5

#include "sysinc.h"
#include "module.h"
#include "comms.h"
#include "common.h"
#include "zbxmedia.h"
#include "log.h"


/* the variable keeps timeout setting for item processing */
static int	item_timeout = 0;

int	zbx_module_unifi_ping(AGENT_REQUEST *request, AGENT_RESULT *result);
int	zbx_module_unifi_proxy(AGENT_REQUEST *request, AGENT_RESULT *result);

static ZBX_METRIC keys[] =
/*      KEY                     FLAG		FUNCTION        	TEST PARAMETERS */
{
	{"unifi.ping",		0,		zbx_module_unifi_ping,	NULL},
	{"unifi.proxy",		CF_HAVEPARAMS,	zbx_module_unifi_proxy, 	"discovery"},
	{NULL}
};

/******************************************************************************
 *                                                                            *
 * Function: zbx_module_api_version                                           *
 *                                                                            *
 * Purpose: returns version number of the module interface                    *
 *                                                                            *
 * Return value: ZBX_MODULE_API_VERSION_ONE - the only version supported by   *
 *               Zabbix currently                                             *
 *                                                                            *
 ******************************************************************************/
int	zbx_module_api_version()
{
	return ZBX_MODULE_API_VERSION_ONE;
}

/******************************************************************************
 *                                                                            *
 * Function: zbx_module_item_timeout                                          *
 *                                                                            *
 * Purpose: set timeout value for processing of items                         *
 *                                                                            *
 * Parameters: timeout - timeout in seconds, 0 - no timeout set               *
 *                                                                            *
 ******************************************************************************/
void	zbx_module_item_timeout(int timeout)
{
	item_timeout = timeout;
}

/******************************************************************************
 *                                                                            *
 * Function: zbx_module_item_list                                             *
 *                                                                            *
 * Purpose: returns list of item keys supported by the module                 *
 *                                                                            *
 * Return value: list of item keys                                            *
 *                                                                            *
 ******************************************************************************/
ZBX_METRIC	*zbx_module_item_list()
{
	return keys;
}

int	zbx_module_unifi_ping(AGENT_REQUEST *request, AGENT_RESULT *result)
{
	SET_UI64_RESULT(result, 1);

	return SYSINFO_RET_OK;
}

int	zbx_module_unifi_proxy(AGENT_REQUEST *request, AGENT_RESULT *result)
{
        int             ret;
        int 		i, p, np;
	char		*param;
        zbx_sock_t	s;
        char		send_buf[MAX_STRING_LEN];

        *send_buf='\0';

        np = request->nparam;
	if (9 < request->nparam)
	{
		/* set optional error message */
		SET_MSG_RESULT(result, strdup("So much parameters."));
		return SYSINFO_RET_FAIL;
	}
        // make request string by concatenate all params
        for (i=0; i < np; i++) 
          {
            strcat(send_buf, get_rparam(request, i));
            p=strlen(send_buf);
            send_buf[p]=(i < (np-1)) ? ',' : '\n';
            send_buf[p+1]='\0';
          }

        // Connect to UniFi Proxy
        if (SUCCEED == (ret = zbx_tcp_connect(&s, CONFIG_SOURCE_IP, UNIFI_PROXY_IP, UNIFI_PROXY_PORT, UNIFI_PROXY_TIMEOUT)))
        {
            // Send request
            if (SUCCEED == (ret = zbx_tcp_send_raw(&s, send_buf)))
               {
                  // Recive answer from UniFi Proxy
                  if (SUCCEED == (ret = zbx_tcp_recv(&s))) {
                        SET_STR_RESULT(result, strdup(s.buffer));
                     }
               }
            zbx_tcp_close(&s);
        }

        if (FAIL == ret)
           {
                zabbix_log(LOG_LEVEL_DEBUG, "UniFi check error: %s", zbx_tcp_strerror());
		SET_MSG_RESULT(result, strdup("Operation error, see log on debug level"));
                return SYSINFO_RET_FAIL;
           }

	return SYSINFO_RET_OK;
}

/******************************************************************************
 *                                                                            *
 * Function: zbx_module_init                                                  *
 *                                                                            *
 * Purpose: the function is called on agent startup                           *
 *          It should be used to call any initialization routines             *
 *                                                                            *
 * Return value: ZBX_MODULE_OK - success                                      *
 *               ZBX_MODULE_FAIL - module initialization failed               *
 *                                                                            *
 * Comment: the module won't be loaded in case of ZBX_MODULE_FAIL             *
 *                                                                            *
 ******************************************************************************/
int	zbx_module_init()
{
	return ZBX_MODULE_OK;
}

/******************************************************************************
 *                                                                            *
 * Function: zbx_module_uninit                                                *
 *                                                                            *
 * Purpose: the function is called on agent shutdown                          *
 *          It should be used to cleanup used resources if there are any      *
 *                                                                            *
 * Return value: ZBX_MODULE_OK - success                                      *
 *               ZBX_MODULE_FAIL - function failed                            *
 *                                                                            *
 ******************************************************************************/
int	zbx_module_uninit()
{
	return ZBX_MODULE_OK;
}
