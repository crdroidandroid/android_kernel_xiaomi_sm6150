// SPDX-License-Identifier: GPL-2.0
/*
 * System optimization for SD730G (6GB RAM) devices.
 * Re-applies kernel tuning after vendor init.rc overrides.
 * Separate file to avoid cherry-pick conflicts in mm/vmscan.c.
 */
#include <linux/delay.h>
#include <linux/file.h>
#include <linux/fs.h>
#include <linux/printk.h>
#include <linux/uaccess.h>
#include <linux/cred.h>
#include <linux/workqueue.h>

extern int vm_swappiness;

static void sysfs_write_str(const char *path, const char *value)
{
	struct file *f;
	loff_t pos = 0;

	f = filp_open(path, O_WRONLY, 0);
	if (IS_ERR(f))
		return;

	kernel_write(f, value, strlen(value), &pos);
	filp_close(f, NULL);
}

static void reapply_optimizations_work(struct work_struct *work);
static DECLARE_DELAYED_WORK(hammerhead_opt, reapply_optimizations_work);

static void reapply_optimizations_work(struct work_struct *work)
{
	static int run_count = 0;
	struct cred *kcred;

	run_count++;

	vm_swappiness = 20;

	/* Elevate to root credentials for sysfs access */
	kcred = prepare_kernel_cred(NULL);
	if (kcred) {
		commit_creds(kcred);

		sysfs_write_str("/sys/block/sda/queue/scheduler", "deadline\n");
		sysfs_write_str("/sys/block/sdb/queue/scheduler", "deadline\n");
		sysfs_write_str("/sys/module/cpu_boost/parameters/sched_boost_on_input", "1\n");
		sysfs_write_str("/sys/module/cpu_boost/parameters/input_boost_freq",
			"0:1804800 1:1804800 2:1804800 3:1804800 4:1804800 5:1804800 6:2208000 7:2208000\n");
		sysfs_write_str("/sys/devices/system/cpu/cpu0/cpufreq/schedutil/down_rate_limit_us", "5000\n");
		sysfs_write_str("/sys/devices/system/cpu/cpu6/cpufreq/schedutil/down_rate_limit_us", "10000\n");
	}

	pr_info("hammerhead_opt: re-apply run %d/4\n", run_count);

	if (run_count < 4)
		schedule_delayed_work(&hammerhead_opt,
			msecs_to_jiffies(run_count == 1 ? 60000 :
					  run_count == 2 ? 120000 : 300000));
}

static int __init hammerhead_init(void)
{
	vm_swappiness = 20;

	pr_info("hammerhead_opt: init - restoring optimized settings after vendor init\n");

	schedule_delayed_work(&hammerhead_opt, msecs_to_jiffies(60000));

	return 0;
}
late_initcall(hammerhead_init);
